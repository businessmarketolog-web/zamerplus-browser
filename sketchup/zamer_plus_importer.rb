# frozen_string_literal: true
require 'sketchup.rb'
require 'extensions.rb'

module ZamerPlus
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('Zamer+ Importer', 'zamer_plus_importer/main')
    ext.description = 'Imports room/project JSON, keeps incoming LAN scans in a safe queue, and creates native geometry.'
    ext.version = '1.1.0'
    ext.creator = 'Zamer+'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
