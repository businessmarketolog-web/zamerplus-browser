# frozen_string_literal: true
require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'base64'
require 'digest'

module ZamerPlus
  module Importer
    extend self

    MM = 1.0.mm
    HALF = 0.5.mm

    def n(v)
      Float(v || 0)
    rescue
      0.0
    end

    def merged_intervals(items)
      return [] if items.empty?
      sorted = items.map(&:dup).sort_by(&:first)
      out = [sorted.shift]
      sorted.each do |cur|
        last = out[-1]
        if cur[0] <= last[1]
          last[1] = [last[1], cur[1]].max
        else
          out << cur
        end
      end
      out
    end

    def build_transform(scan)
      walls = scan['walls'] || []
      selected = scan['_baseWallId'] && walls.find { |w| w['id'] == scan['_baseWallId'] }
      ref = selected || walls.max_by { |w| n(w['widthMm']).positive? ? n(w['widthMm']) : Math.hypot(n(w['x2Mm'])-n(w['x1Mm']), n(w['z2Mm'])-n(w['z1Mm'])) }
      raise 'No walls' unless ref
      x1,z1,x2,z2 = n(ref['x1Mm']),n(ref['z1Mm']),n(ref['x2Mm']),n(ref['z2Mm'])
      if scan['_reverseBase']
        x1,x2 = x2,x1
        z1,z2 = z2,z1
      end
      bx = x2-x1
      by = -(z2-z1)
      angle = Math.atan2(by,bx)
      c = Math.cos(angle); s = Math.sin(angle)
      q = (n(scan['_rotationQuarterTurns']).to_i % 4) * Math::PI/2.0
      qc = Math.cos(q); qs = Math.sin(q)
      lambda do |x,z|
        dx = n(x)-x1
        dy = -(n(z)-z1)
        px = dx*c + dy*s
        py = -dx*s + dy*c
        [px*qc-py*qs, px*qs+py*qc]
      end
    end

    def wall_frame(scan, wall, xf)
      a = xf.call(wall['x1Mm'], wall['z1Mm'])
      raw_b = xf.call(wall['x2Mm'], wall['z2Mm'])
      raw_l = Math.hypot(raw_b[0]-a[0], raw_b[1]-a[1])
      raw_l = 1.0 if raw_l <= 0.0
      len = n(wall['widthMm']).positive? ? n(wall['widthMm']) : raw_l
      ux = (raw_b[0]-a[0])/raw_l
      uy = (raw_b[1]-a[1])/raw_l
      h = [1.0, n(wall['heightMm']).positive? ? n(wall['heightMm']) : n(scan['heightMm'])].max
      {a:a, ux:ux, uy:uy, len:len, h:h}
    end

    def p3(x,y,z)
      Geom::Point3d.new(x.mm, y.mm, z.mm)
    end

    def dim_vec(f, distance)
      Geom::Vector3d.new((-f[:uy]*distance).mm, (f[:ux]*distance).mm, 0)
    end

    def add_dim(entities, a, b, offset, layer)
      dim = entities.add_dimension_linear(a, b, offset)
      dim.layer = layer if dim
      dim
    rescue
      nil
    end

    def add_prism(entities, p1, p2, z0, z1)
      dx = p2[0]-p1[0]; dy = p2[1]-p1[1]
      l = Math.hypot(dx,dy)
      return if l <= 0
      nx = -dy/l*0.5
      ny = dx/l*0.5
      a=[p1[0]+nx,p1[1]+ny]; b=[p2[0]+nx,p2[1]+ny]
      c=[p2[0]-nx,p2[1]-ny]; d=[p1[0]-nx,p1[1]-ny]
      pts=[
        p3(a[0],a[1],z0),p3(b[0],b[1],z0),p3(c[0],c[1],z0),p3(d[0],d[1],z0),
        p3(a[0],a[1],z1),p3(b[0],b[1],z1),p3(c[0],c[1],z1),p3(d[0],d[1],z1)
      ]
      [[0,1,2,3],[4,7,6,5],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]].each do |idx|
        face=entities.add_face(idx.map{|i|pts[i]})
        face.reverse! if face && face.normal.z < 0 && idx[0] == 4
      end
    end

    def import_room(payload, model, container = nil, source = 'manual')
      scan = payload['scan'] || {}
      walls = scan['walls'] || []
      raise 'No walls in scan' if walls.empty?
      walls_tag = model.layers['Zamer+ Walls'] || model.layers.add('Zamer+ Walls')
      floor_tag = model.layers['Zamer+ Floor'] || model.layers.add('Zamer+ Floor')
      dims_tag  = model.layers['Zamer+ Dimensions'] || model.layers.add('Zamer+ Dimensions')
      root = (container ? container.entities : model.active_entities).add_group
      root.name = "#{payload['projectName']} — #{payload['roomName']}"
      root.set_attribute('ZamerPlus','source',source)
      root.set_attribute('ZamerPlus','exportedAt',payload['exportedAt'].to_s)
      root.set_attribute('ZamerPlus','roomId',payload['roomId'].to_s)
      root.set_attribute('ZamerPlus','revisionId',payload['revisionId'].to_s)
      root.set_attribute('ZamerPlus','placementVerified',payload.dig('placement','verified') == true)

      xf = build_transform(scan)
      openings = scan['openings'] || []

      walls.each_with_index do |w,i|
        f = wall_frame(scan,w,xf)
        wg = root.entities.add_group
        wg.name = "Wall_#{i+1}"
        wg.layer = walls_tag
        ops = openings.select{|o|o['parentId']==w['id']}
        bounds=[0.0,f[:len]]
        ops.each do |o|
          off=[[0.0,n(o['offsetMm'])].max,f[:len]].min
          ow=[0.0,n(o['widthMm'])].max
          bounds << off << [f[:len],off+ow].min
        end
        bounds=bounds.uniq.sort
        (0...(bounds.length-1)).each do |bi|
          x0,x1=bounds[bi],bounds[bi+1]
          mid=(x0+x1)/2.0
          blocked=[]
          ops.each do |o|
            off=[[0.0,n(o['offsetMm'])].max,f[:len]].min
            ow=[0.0,n(o['widthMm'])].max
            next unless mid>=off && mid<=off+ow
            bot=[0.0,n(o['bottomMm'])].max
            oh=[0.0,n(o['heightMm'])].max
            blocked << [bot,[f[:h],bot+oh].min]
          end
          blocked=merged_intervals(blocked)
          solids=[]; cur=0.0
          blocked.each do |q|
            solids << [cur,q[0]] if q[0]>cur
            cur=[cur,q[1]].max
          end
          solids << [cur,f[:h]] if cur<f[:h]
          p1=[f[:a][0]+f[:ux]*x0,f[:a][1]+f[:uy]*x0]
          p2=[f[:a][0]+f[:ux]*x1,f[:a][1]+f[:uy]*x1]
          solids.each{|q|add_prism(wg.entities,p1,p2,q[0],q[1]) if q[1]-q[0] >= 1.0 && x1-x0 >= 1.0}
        end

        add_dim(
          root.entities,
          p3(f[:a][0],f[:a][1],0),
          p3(f[:a][0]+f[:ux]*f[:len],f[:a][1]+f[:uy]*f[:len],0),
          dim_vec(f,300),
          dims_tag
        )

        ops.each_with_index do |o, oi|
          off = [[0.0,n(o['offsetMm'])].max,f[:len]].min
          ow  = [0.0,n(o['widthMm'])].max
          oh  = [0.0,n(o['heightMm'])].max
          bot = [0.0,n(o['bottomMm'])].max
          ax = f[:a][0] + f[:ux]*off
          ay = f[:a][1] + f[:uy]*off
          bx = ax + f[:ux]*ow
          by = ay + f[:uy]*ow

          add_dim(root.entities, p3(ax,ay,bot), p3(bx,by,bot), dim_vec(f,170), dims_tag)
          add_dim(root.entities, p3(bx,by,bot), p3(bx,by,bot+oh), dim_vec(f,120), dims_tag)
          add_dim(root.entities, p3(f[:a][0],f[:a][1],0), p3(ax,ay,0), dim_vec(f,90), dims_tag) if off > 0.5
          add_dim(root.entities, p3(ax,ay,0), p3(ax,ay,bot), dim_vec(f,240), dims_tag) if bot > 0.5

          label = (o['type'] || 'opening').to_s.capitalize
          txt = root.entities.add_text("#{label} #{ow.round}x#{oh.round}", p3((ax+bx)/2.0,(ay+by)/2.0,bot+oh+80))
          txt.layer = dims_tag if txt
        end
      end

      if walls.any?
        base_wall = scan['_baseWallId'] && walls.find { |w| w['id'] == scan['_baseWallId'] }
        base_wall ||= walls.first
        hf = wall_frame(scan, base_wall, xf)
        add_dim(
          root.entities,
          p3(hf[:a][0],hf[:a][1],0),
          p3(hf[:a][0],hf[:a][1],hf[:h]),
          dim_vec(hf,450),
          dims_tag
        )
      end

      poly = scan['floorPolygon'] || []
      if poly.length >= 3
        fg=root.entities.add_group
        fg.name='Floor'
        fg.layer=floor_tag
        pts=poly.map{|q|xy=xf.call(q['xMm'],q['zMm']);p3(xy[0],xy[1],0)}
        face=fg.entities.add_face(pts)
        face.reverse! if face && face.normal.z < 0
      end

      add_notes(root, payload, scan, xf, model)
      root
    end

    def add_notes(root, payload, scan, xf, model)
      notes = payload['notes'] || {}
      return if notes.empty?
      tag = model.layers['Zamer+ Notes'] || model.layers.add('Zamer+ Notes')
      photo_tag = model.layers['Zamer+ Photos'] || model.layers.add('Zamer+ Photos')
      photo_tag.visible = false
      assets = File.join(Dir.home, 'Documents', 'ZamerPlus', 'Assets')
      FileUtils.mkdir_p(assets)
      walls = scan['walls'] || []
      notes.each do |id, value|
        next unless value.is_a?(Hash)
        element_wall = walls.find { |w| w['id'].to_s == id.to_s }
        opening = (scan['openings'] || []).find { |o| o['id'].to_s == id.to_s }
        element_wall ||= walls.find { |w| w['id'].to_s == opening['parentId'].to_s } if opening
        f = element_wall ? wall_frame(scan, element_wall, xf) : nil
        xy = f ? f[:a] : [0,0]
        label = value['label'].to_s[0,80]
        text = value['text'].to_s[0,2500]
        root.set_attribute('ZamerPlus','note_'+id.to_s[0,80],JSON.generate({'label'=>label,'text'=>text}))
        unless text.empty?
          t = root.entities.add_text("#{label}: #{text}", p3(xy[0],xy[1], f ? f[:h]+250 : 3000))
          t.layer = tag if t
        end
        photo = value['photo'].to_s
        next unless photo.start_with?('data:image/jpeg;base64,') && photo.bytesize <= 240000
        begin
          data = Base64.strict_decode64(photo.split(',',2)[1])
          next if data.bytesize > 180000
          filename = File.join(assets, Digest::SHA256.hexdigest(data)+'.jpg')
          File.binwrite(filename,data) unless File.file?(filename)
          root.set_attribute('ZamerPlus','photo_'+id.to_s[0,80],filename)
          img = root.entities.add_image(filename,p3(xy[0],xy[1], f ? f[:h]+450 : 3500),450.mm)
          img.layer = photo_tag if img
        rescue => e
          root.set_attribute('ZamerPlus','photo_error_'+id.to_s[0,80],e.message)
        end
      end
    end

    def import_payload(payload, source = 'manual', silent = false)
      kind = payload['format']
      raise 'Not a Zamer+ JSON file' unless ['zamerplus-sketchup','zamerplus-project'].include?(kind)
      model = Sketchup.active_model
      model.start_operation('Import Zamer+ LiDAR', true)
      if kind == 'zamerplus-project'
        rooms = payload['rooms'] || []
        raise 'Project has no rooms' if rooms.empty?
        parent = model.active_entities.add_group
        parent.name = payload['projectName'].to_s
        parent.set_attribute('ZamerPlus','projectId',payload['projectId'].to_s)
        rooms.each do |room|
          part = room.merge('projectName' => payload['projectName'], 'exportedAt' => payload['exportedAt'])
          g = import_room(part, model, parent, source)
          pose = room['placement'] || {}
          x = n(pose['xMm']); y = n(pose['yMm'])
          angle = n(pose['rotationDeg']).degrees
          g.transformation = Geom::Transformation.translation([x.mm,y.mm,0]) * Geom::Transformation.rotation(ORIGIN,Z_AXIS,angle)
        end
        result = parent
      else
        result = import_room(payload, model, nil, source)
      end
      model.commit_operation
      model.active_view.zoom(result)
      UI.messagebox('Zamer+ imported successfully') unless silent
      result
    rescue => e
      model.abort_operation if defined?(model) && model
      UI.messagebox("Zamer+ import error:\n#{e.message}") unless silent
      raise if silent
      nil
    end

    def import_file(path, silent = false)
      payload = JSON.parse(File.read(path, encoding: 'UTF-8'))
      import_payload(payload, path, silent)
    rescue => e
      UI.messagebox("Zamer+ import error:\n#{e.message}") unless silent
      nil
    end

    def inbox_root
      File.join(Dir.home,'Documents','ZamerPlus')
    end

    def pending_files
      dir=File.join(inbox_root,'Inbox')
      return [] unless Dir.exist?(dir)
      Dir.glob(File.join(dir,'*.zamer.json')).sort
    end

    def empty_model?(model)
      model.path.to_s.empty? && model.entities.empty? && (!model.respond_to?(:modified?) || !model.modified?)
    end

    def import_pending(force = false)
      return if @busy
      path=pending_files.first
      return unless path
      model=Sketchup.active_model
      if !empty_model?(model)
        return unless force
        Sketchup.file_new
        model=Sketchup.active_model
        return unless model.path.to_s.empty? && model.entities.empty?
      end
      @busy=true
      result=import_file(path,true)
      raise 'Cannot import pending Zamer+ scan' unless result
      output=File.join(inbox_root,'Models')
      FileUtils.mkdir_p(output)
      base=File.basename(path,'.zamer.json')
      destination=File.join(output,base+'.skp')
      raise 'SketchUp did not save the new model' unless model.save(destination)
      completed=File.join(inbox_root,'Processed')
      FileUtils.mkdir_p(completed)
      FileUtils.mv(path,File.join(completed,File.basename(path)))
      UI.messagebox('Замер+ — готово. Модель сохранена: '+destination) if force
      destination
    rescue => e
      FileUtils.mkdir_p(File.join(inbox_root,'Failed'))
      File.write(File.join(inbox_root,'Failed',File.basename(path)+'.txt'),e.message) if path
      FileUtils.mv(path,File.join(inbox_root,'Failed',File.basename(path))) if path && File.file?(path)
      UI.messagebox('Замер+ — ошибка импорта: '+e.message) if force
      nil
    ensure
      @busy=false
    end

    def inbox_status
      'В очереди: '+pending_files.length.to_s+' · папка '+File.join(inbox_root,'Inbox')
    end

    unless file_loaded?(__FILE__)
      UI.menu('Extensions').add_item('Zamer+ — Import LiDAR JSON') do
        path=UI.openpanel('Import Zamer+ JSON', nil, 'JSON Files|*.json;*.zamer.json||')
        import_file(path) if path
      end
      UI.menu('Extensions').add_item('Zamer+ — Импортировать входящий скан в новую модель') { import_pending(true) }
      UI.menu('Extensions').add_item('Zamer+ — Очередь сканов') { UI.messagebox(inbox_status) }
      UI.start_timer(4.0,true) { import_pending(false) }
      file_loaded(__FILE__)
    end
  end
end
