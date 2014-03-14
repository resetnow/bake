require 'rgen/metamodel_builder'
require 'rgen/metamodel_builder/data_types'

module Cxxproject

  module Metamodel
    extend RGen::MetamodelBuilder::ModuleExtension

    class ModelElement < RGen::MetamodelBuilder::MMBase
      abstract
      has_attr 'line_number', Integer do
        annotation :details => {'internal' => 'true'}
      end
      has_attr 'file_name', String do
        annotation :details => {'internal' => 'true'}
      end
      module ClassModule
      	attr_accessor :fragment_ref
      	
      	def id
          splitted = file_name.split("/")
          splitted[splitted.length-2]
        end      	
      	
      end
    end

    CompilerType = RGen::MetamodelBuilder::DataTypes::Enum.new([:CPP, :C, :ASM])

    class Flags < ModelElement
      has_attr 'overwrite', String, :defaultValueLiteral => ""
      has_attr 'add', String, :defaultValueLiteral => ""
      has_attr 'remove', String, :defaultValueLiteral => ""
    end
    class LibPrefixFlags < ModelElement
      has_attr 'overwrite', String, :defaultValueLiteral => ""
      has_attr 'add', String, :defaultValueLiteral => ""
      has_attr 'remove', String, :defaultValueLiteral => ""
    end
    class LibPostfixFlags < ModelElement
      has_attr 'overwrite', String, :defaultValueLiteral => ""
      has_attr 'add', String, :defaultValueLiteral => ""
      has_attr 'remove', String, :defaultValueLiteral => ""
    end
    class Define < ModelElement
      has_attr 'str', String, :defaultValueLiteral => ""
    end


      class Archiver < ModelElement
        has_attr 'command', String, :defaultValueLiteral => ""
        contains_many 'flags', Flags, 'parent'
      end

      class Linker < ModelElement
        has_attr 'command', String, :defaultValueLiteral => ""
        contains_many 'flags', Flags, 'parent'
        contains_many 'libprefixflags', LibPrefixFlags, 'parent'
        contains_many 'libpostfixflags', LibPostfixFlags, 'parent'
      end

      class Compiler < ModelElement
        has_attr 'ctype', CompilerType
        has_attr 'command', String, :defaultValueLiteral => ""
        contains_many 'define', Define, 'parent'
        contains_many 'flags', Flags, 'parent'
      end

      class LintPolicy < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
      end      
      
      class DefaultToolchain < ModelElement
        has_attr 'basedOn', String, :defaultValueLiteral => ""
        contains_many 'compiler', Compiler, 'parent'
        contains_one 'archiver', Archiver, 'parent'
        contains_one 'linker', Linker, 'parent'
        contains_many 'lintPolicy', LintPolicy, 'parent'
      end

      class Toolchain < ModelElement
        contains_many 'compiler', Compiler, 'parent'
        contains_one 'archiver', Archiver, 'parent'
        contains_one 'linker', Linker, 'parent'
        contains_many 'lintPolicy', LintPolicy, 'parent'
      end
      
      class Person < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
        has_attr 'email', String, :defaultValueLiteral => ""
      end

      class Responsible < ModelElement
        contains_many "person", Person, 'parent'
      end

      class Files < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
        contains_many 'define', Define, 'parent'
        contains_many 'flags', Flags, 'parent'
      end

      class ExcludeFiles < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
      end

      class IncludeDir < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
      end

      class ExternalLibrary < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
        has_attr 'search', Boolean, :defaultValueLiteral => "true"
      end

      class ExternalLibrarySearchPath < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
      end

      class Step < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
        has_attr 'default', String, :defaultValueLiteral => "on"
        has_attr 'filter', String, :defaultValueLiteral => ""
      end

      class Makefile < Step
        has_attr 'lib', String, :defaultValueLiteral => ""
        has_attr 'target', String, :defaultValueLiteral => ""
        has_attr 'pathTo', String, :defaultValueLiteral => ""
        contains_many 'flags', Flags, 'parent'
      end

      class CommandLine < Step
      end

      class PreSteps < ModelElement
        contains_many 'step', Step, 'parent'
      end

      class PostSteps < ModelElement
        contains_many 'step', Step, 'parent'
      end

      class UserLibrary < ModelElement
        has_attr 'lib', String, :defaultValueLiteral => ""
      end

      class LinkerScript < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
      end

      class MapFile < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
      end
      
      class ArtifactName < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
      end      

      class BaseConfig_INTERNAL < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
        has_attr 'extends', String, :defaultValueLiteral => ""
        contains_one 'preSteps', PreSteps, 'parent'
        contains_one 'postSteps', PostSteps, 'parent'
        contains_many 'userLibrary', UserLibrary, 'parent'
        contains_many 'exLib', ExternalLibrary, 'parent'
        contains_many 'exLibSearchPath', ExternalLibrarySearchPath, 'parent'
        contains_one 'defaultToolchain', DefaultToolchain, 'parent'
        
        module ClassModule
      	  def ident
      	    s = file_name.split("/")
            s[s.length-2] + "/" + name
          end      	
        end
        
      end
      
      class BuildConfig_INTERNAL < BaseConfig_INTERNAL
        contains_many 'files', Files, 'parent'
        contains_many 'excludeFiles', ExcludeFiles, 'parent'
        contains_many 'includeDir', IncludeDir, 'parent'
        contains_one 'toolchain', Toolchain, 'parent'
        
        module ClassModule
      	  def ident
      	    s = file_name.split("/")
            s[s.length-2] + "/" + name
          end      	
        end
        
      end      
      
      class ExecutableConfig < BuildConfig_INTERNAL
        contains_one 'linkerScript', LinkerScript, 'parent'
        contains_one 'artifactName', ArtifactName, 'parent'
        contains_one 'mapFile', MapFile, 'parent'
      end
      
      class LibraryConfig < BuildConfig_INTERNAL
      end

      class CustomConfig < BaseConfig_INTERNAL
        contains_one 'step', Step, 'parent'
      end

      class Project < ModelElement
        #has_attr 'name', String  do
        #  annotation :details => {'internal' => 'true'}
        #end
        contains_one 'responsible', Responsible, 'parent'
        contains_many 'config', BaseConfig_INTERNAL, 'parent'
        
        module ClassModule
      	  def name
            splitted = file_name.split("/")
            x = splitted[splitted.length-2]
            x
          end      	
        end
                
      end

      class Dependency < ModelElement
        has_attr 'name', String, :defaultValueLiteral => ""
        has_attr 'config', String, :defaultValueLiteral => ""
      end

      BaseConfig_INTERNAL.contains_many 'dependency', Dependency, 'parent'

  end

end
