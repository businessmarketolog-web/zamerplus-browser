class Numeric
  def mm
    self
  end
end
def file_loaded?(_)
  true
end
load File.expand_path('../sketchup/zamer_plus_importer/main.rb',__dir__)
scan = {'walls'=>[{'id'=>'w1','widthMm'=>4000,'x1Mm'=>0,'z1Mm'=>0,'x2Mm'=>4000,'z2Mm'=>0}]}
xf = ZamerPlus::Importer.build_transform(scan)
def check(p, x,y)
  raise "wrong point #{p.inspect} expected #{x},#{y}" unless (p[0]-x).abs<0.0001 && (p[1]-y).abs<0.0001
end
check(xf.call(0,0),0,0)
check(xf.call(4000,0),4000,0)
check(xf.call(4000,1000),4000,-1000)
scan['_rotationQuarterTurns']=1
check(ZamerPlus::Importer.build_transform(scan).call(4000,0),0,4000)
puts 'PASS: SketchUp transform preserves handedness and rotates without mirroring'

class SketchUpEntitiesWithoutEmpty
  def initialize(count)
    @count=count
  end
  def length
    @count
  end
end
class FakeSketchUpModel
  def initialize(count)
    @entities=SketchUpEntitiesWithoutEmpty.new(count)
  end
  def path
    ''
  end
  def entities
    @entities
  end
end
raise 'SketchUp::Entities count check failed' unless ZamerPlus::Importer.empty_model?(FakeSketchUpModel.new(0))
raise 'Importer accepted a nonempty scene' if ZamerPlus::Importer.empty_model?(FakeSketchUpModel.new(3))
puts 'PASS: empty model check supports SketchUp::Entities without empty?'
