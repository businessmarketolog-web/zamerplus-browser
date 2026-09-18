# frozen_string_literal: true
require 'sketchup.rb'
require 'json'

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

    def import_file(path)
      payload = JSON.parse(File.read(path, encoding:'UTF-8'))
      raise 'Not a Zamer+ SketchUp JSON file' unless payload['format'] == 'zamerplus-sketchup'
      scan = payload['scan'] || {}
      walls = scan['walls'] || []
      raise 'No walls in scan' if walls.empty?

      model = Sketchup.active_model
      model.start_operation('Import Zamer+ LiDAR', true)

      walls_tag = model.layers['Zamer+ Walls'] || model.layers.add('Zamer+ Walls')
      floor_tag = model.layers['Zamer+ Floor'] || model.layers.add('Zamer+ Floor')
      dims_tag  = model.layers['Zamer+ Dimensions'] || model.layers.add('Zamer+ Dimensions')

      root = model.active_entities.add_group
      root.name = "#{payload['projectName']} — #{payload['roomName']}"
      root.set_attribute('ZamerPlus','source',path)
      root.set_attribute('ZamerPlus','exportedAt',payload['exportedAt'].to_s)

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

        dim_offset = Geom::Vector3d.new((-f[:uy]*300).mm,(f[:ux]*300).mm,0)
        dim = root.entities.add_dimension_linear(p3(f[:a][0],f[:a][1],0),p3(f[:a][0]+f[:ux]*f[:len],f[:a][1]+f[:uy]*f[:len],0),dim_offset)
        dim.layer=dims_tag if dim
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

      model.commit_operation
      model.active_view.zoom(root)
      UI.messagebox("Zamer+ imported: #{walls.length} walls")
      true
    rescue => e
      model.abort_operation if defined?(model) && model
      UI.messagebox("Zamer+ import error:\n#{e.message}")
      false
    end

    unless file_loaded?(__FILE__)
      UI.menu('Extensions').add_item('Zamer+ — Import LiDAR JSON') do
        path=UI.openpanel('Import Zamer+ JSON', nil, 'JSON Files|*.json;*.zamer.json||')
        import_file(path) if path
      end
      file_loaded(__FILE__)
    end
  end
end
