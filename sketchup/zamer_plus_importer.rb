# frozen_string_literal: true
require 'sketchup.rb'
require 'extensions.rb'

module ZamerPlus
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('Zamer+ Importer', 'zamer_plus_importer/main')
    ext.description = 'Imports manually selected Zamer+ room/project JSON files as native SketchUp geometry.'
    ext.version = '1.2.0'
    ext.creator = 'Zamer+'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
