require 'blocks/compile'

module Bake
  
  module Blocks
    
    class Convert < Compile
      
      def initialize(block, config, referencedConfigs, tcs)
        super(block, config, referencedConfigs, tcs)
      end
   
      def execute
        Dir.chdir(@projectDir) do
          calcSources
                
          puts "START_INFO"
          puts " BAKE_SOURCES"
          @source_files.each { |s| puts "  #{s}" }
          puts " BAKE_INCLUDES"
          @include_list.each { |s| puts "  #{s}" }
          puts " BAKE_DEFINES"
          (@tcs[:COMPILER][:CPP][:DEFINES] + @tcs[:COMPILER][:C][:DEFINES] + @tcs[:COMPILER][:ASM][:DEFINES]).uniq.each { |s| puts "  #{s}" }
          puts "END_INFO"
        end
      end
      
      def clean
        # nothing to do here
      end
      
    end
    
  end
end