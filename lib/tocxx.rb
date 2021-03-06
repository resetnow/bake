#!/usr/bin/env ruby


require_relative 'bake/model/metamodel_ext'

require_relative 'bake/util'
require_relative 'bake/cache'
require_relative 'bake/subst'
require_relative 'bake/mergeConfig'

require_relative 'common/exit_helper'
require_relative 'common/ide_interface'
require_relative 'common/ext/file'
require_relative 'bake/toolchain/provider'
require_relative 'common/ext/stdout'
require_relative 'common/utils'
require_relative 'bake/toolchain/colorizing_formatter'
require_relative 'bake/config/loader'

require_relative 'blocks/block'
require_relative 'blocks/commandLine'
require_relative 'blocks/sleep'
require_relative 'blocks/fileutil'
require_relative 'blocks/makefile'
require_relative 'blocks/compile'
require_relative 'blocks/convert'
require_relative 'blocks/library'
require_relative 'blocks/executable'
require_relative 'blocks/docu'

require 'set'
require 'socket'

require_relative 'blocks/showIncludes'
require_relative 'common/abortException'

require_relative 'adapt/config/loader'
require "thwait"
require 'pathname'

module Bake

  class SystemCommandFailed < Exception
  end

  class ToCxx

    @@linkBlock = 0
    @@include_deps = {}

    def self.linkBlock
      @@linkBlock = 1
    end
    
    def self.include_deps
      @@include_deps
    end

    def self.reset_include_deps
      @@include_deps = {}
    end

    def initialize
      @configTcMap = {}
    end

    def createBaseTcsForConfig
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          tcs = Utils.deep_copy(@defaultToolchain)
          @configTcMap[config] = tcs
        end
      end
    end

    def createTcsForConfig
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          integrateToolchain(@configTcMap[config], config.toolchain)
        end
      end
    end

    def substVars
      Subst.itute(@mainConfig, Bake.options.main_project_name, true, @configTcMap[@mainConfig], @referencedConfigs, @configTcMap)
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          if config != @mainConfig
            Subst.itute(config, projName, false, @configTcMap[config], @referencedConfigs, @configTcMap)
          end
        end
      end
      Subst.resolveOutputDir
    end

    def addLib(block, configSteps)
      Array(configSteps.step).each do |step|
        if Bake::Metamodel::Makefile === step
          block.lib_elements << LibElement.new(LibElement::LIB_WITH_PATH, step.lib) if step.lib != ""
        end
      end if configSteps
    end

    def addSteps(block, blockSteps, configSteps)
      Array(configSteps.step).each do |step|
        if Bake::Metamodel::Makefile === step
          blockSteps << Blocks::Makefile.new(step, @referencedConfigs, block)
        elsif Bake::Metamodel::CommandLine === step
          blockSteps << Blocks::CommandLine.new(step)
        elsif Bake::Metamodel::Sleep === step
          blockSteps << Blocks::Sleep.new(step)
        elsif Bake::Metamodel::Move === step
          blockSteps << Blocks::FileUtil.new(step, :move, block.projectDir)
        elsif Bake::Metamodel::Copy === step
          blockSteps << Blocks::FileUtil.new(step, :copy, block.projectDir)
        elsif Bake::Metamodel::Remove === step
          blockSteps << Blocks::FileUtil.new(step, :remove, block.projectDir)
        elsif Bake::Metamodel::MakeDir === step
          blockSteps << Blocks::FileUtil.new(step, :makedir, block.projectDir)
        elsif Bake::Metamodel::Touch === step
          blockSteps << Blocks::FileUtil.new(step, :touch, block.projectDir)
        end
      end if configSteps
    end

    def addSubDependencies(block, config)
      subDeps = []
      config.depInc.each do |dep|
        if (Metamodel::Dependency === dep)
          @referencedConfigs[dep.name].each do |configRef|
            if configRef.name == dep.config
              blockRef = Blocks::ALL_BLOCKS[configRef.qname]
              break if blockRef.visited
              blockRef.visited = true

              subDeps += addSubDependencies(block, configRef)
              subDeps << dep
              break
            end
          end
        else
          subDeps << dep if dep.inherit
        end
          
      end
      @correctOrder << Blocks::ALL_BLOCKS[config.qname] if @corOrderActive
      return subDeps
    end
    
    def addIncludes(block, config)
      return if !config.respond_to?("includeDir")
      config.includeDir.each do |inc|
        if inc.inject == "front" || inc.infix == "front"
          
        elsif inc.inject == "back" || inc.infix == "back"
        
        end
      end
    
    end

    def addDependencies(block, config)
      Blocks::ALL_BLOCKS.each do |bname, b|
        b.visited = false
      end
      block.visited = true

      block.bes = []
      block.besDirect = []
      block.config.depInc.each do |dep|
        if (Metamodel::Dependency === dep)
          @referencedConfigs[dep.name].each do |configRef|
            if configRef.name == dep.config
              qname = configRef.qname
              blockRef = Blocks::ALL_BLOCKS[qname]
  
              if configRef.private && configRef.parent.name != config.parent.name
                Bake.formatter.printError("#{config.parent.name} (#{config.name}) depends on #{configRef.parent.name} (#{configRef.name}) which is private.", configRef)
                ExitHelper.exit(1)
              end
  
              block.dependencies << qname if not Bake.options.project# and not Bake.options.filename
              if !blockRef.visited
                blockRef.visited = true
                subDeps = addSubDependencies(block, configRef)
                block.bes += subDeps
              end
              block.bes << dep
              block.besDirect << dep
              break
            end
          end
        else
          block.bes << dep
        end
      end
      
    end

    def calcPrebuildBlocks
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          if config.prebuild
            @prebuild ||= {}
            config.prebuild.except.each do |except|
              pName = projName
              if not except.name.empty?
                if not @referencedConfigs.keys.include? except.name
                  Bake.formatter.printInfo("Info: prebuild project #{except.name} not found")
                  next
                end
                pName = except.name
              end
              if except.config != "" && !@referencedConfigs[pName].any? {|config| config.name == except.config}
                Bake.formatter.printWarning("Warning: prebuild config #{except.config} of project #{pName} not found")
                next
              end

              if not @prebuild.include?pName
                @prebuild[pName] = [except.config]
              else
                @prebuild[pName] << except.config
              end
            end
          end
        end
      end
    end

    def makeBlocks
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|

          prebuild = !@prebuild.nil?
          if @prebuild and @prebuild.has_key?projName
            prebuild = false if (@prebuild[projName].include?"" or @prebuild[projName].include?config.name)
          end

          block = Blocks::Block.new(config, @referencedConfigs, prebuild, @configTcMap[config])
          Blocks::ALL_BLOCKS[config.qname] = block
        end
      end
    end
    
    def makeDepOverview
      return if !Bake.options.dev_features.any? {|feature| feature.start_with?("dep-overview=") }
      Blocks::ALL_BLOCKS.each do |name,block|
        block.bes.each do |depInc|
          @@include_deps[block.projectDir] = Set.new if !@@include_deps.has_key?(block.projectDir)
          if (Metamodel::Dependency === depInc)
            c = @referencedConfigs[depInc.name].detect { |configRef| configRef.name == depInc.config }
            @@include_deps[block.projectDir] << Blocks::ALL_BLOCKS[c.qname].projectDir
          else
            @@include_deps[block.projectDir] << depInc.name
          end
        end
      end
      ExitHelper.exit(0)
    end
    
    def makeIncs
      Blocks::ALL_BLOCKS.each do |name,block|
        bes2 = []
        block.bes.each do |inc|
          rootsFound = false
          if Metamodel::IncludeDir === inc
            if inc.name == "___ROOTS___"
              Bake.options.roots.each do |r|
                i = Metamodel::IncludeDir.new
                i.name = r.dir
                i.inherit = inc.inherit
                i.inject = inc.inject
                i.infix = inc.infix
                i.parent = inc.parent
                bes2 << i
              end
              rootsFound = true
            else
              if inc.parent == block.config 
                Dir.chdir(block.projectDir) do
                  i = block.convPath(inc,nil,true)
                  inc.name  = File.expand_path(Pathname.new(i).cleanpath)
                end
              end
            end
          end
          bes2 << inc if !rootsFound
        end
        block.bes = bes2
      end
    end

    def makeGraph
      mainConfig = @referencedConfigs[Bake.options.main_project_name].select { |c| c.name == Bake.options.build_config }.first
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          block = Blocks::ALL_BLOCKS[config.qname]
          if (config == mainConfig)
            @correctOrder = []
            @corOrderActive = true
          end
          addDependencies(block, config)
          if (config == mainConfig)
            @correctOrder.unshift(block)
            @corOrderActive = false
          end
        end
      end
      Blocks::ALL_BLOCKS.each do |name,block|
        block.dependencies.uniq!
      end

      # inject dependencies
      num_interations = 0
      begin
        if (num_interations > 0) and Bake.options.debug and Bake.options.verbose >= 3
          puts "Inject dependencies, iteration #{num_interations}:"
          Blocks::ALL_BLOCKS.each do |name,block|
            puts block.config.qname
            block.bes.select{|b| Metamodel::Dependency === b}.each { |d| puts "- #{d.name},#{d.config}" }
          end
        end

        counter = 0
        @correctOrder.reverse.each do |block|
          name = block.config.qname
          difr = []
          diba = []
          block.bes.each do |d|
            if Metamodel::Dependency === d
              next if d.inject == ""
              dqname = "#{d.name},#{d.config}"
              next if name == dqname
              if d.inject == "front"
                difr << d
              elsif d.inject == "back"
                diba << d
              end
              d.inject = "" # this prevents injecting to injected deps
              d.setInjected
            elsif Metamodel::IncludeDir === d
              if d.inject == "front" || d.infix == "front"
                difr << d
              elsif d.inject == "back" || d.infix == "back" 
                diba << d
              end
              d.inject = "" # this prevents injecting to injected deps
              d.infix = ""
            end
          end
          next if difr.empty? && diba.empty?

          block.bes.each do |dep|
            next unless Metamodel::Dependency === dep
            difr2 = difr.select{|d| Metamodel::IncludeDir === d || d != dep}
            diba2 = diba.select{|d| Metamodel::IncludeDir === d || d != dep}
            fde = Blocks::ALL_BLOCKS[dep.name+","+dep.config]
            l1 = fde.bes.length 
            fde.bes = (difr2 + fde.bes + diba2).uniq
            fde.besDirect = (difr2 + fde.besDirect + diba2).uniq
            l2 = fde.bes.length
            counter += 1 if (l2 != l1)
          end
        end
        num_interations += 1
      end while counter > 0
    end

    def makeUniq
      Blocks::ALL_BLOCKS.each do |name,block|
        bes2 = []
        blockSet = Set.new
        block.bes.each do |b|
          n = Metamodel::Dependency === b ? b.name+","+b.config : b.name + "," + b.inherit.to_s
          next if blockSet.include?n
          blockSet << n
          bes2 << b
        end
        block.bes = bes2
      end
    end

    def makeDot
        if Bake.options.dotFilename
          filename = Bake.options.dotFilename
        else
          filename = Bake.options.main_dir + "/" + Bake.options.build_config + ".dot"
        end
        File.open(filename, 'w') do |file|
          puts "Creating #{filename}"

          onlyProjectName = nil
          onlyConfigName = nil
          if Bake.options.project
            splitted = Bake.options.project.split(',')
            onlyProjectName = splitted[0]
            onlyConfigName = splitted[1] if splitted.length == 2
          end

          file.write "# Generated by bake\n"
          file.write "# Example to show the graph: dot #{File.basename(filename)} -Tpng -o out.png\n"
          file.write "# Example to reduce the graph: tred #{File.basename(filename)} | dot -Tpng -o out.png\n\n"

          if onlyProjectName
            starting = onlyProjectName
            if onlyConfigName
              ending = Bake.options.dotShowProjOnly ? "" : "_"+onlyConfigName
            else
              ending = ""
            end
          else
            starting = Bake.options.main_project_name
            ending = Bake.options.dotShowProjOnly ? "" : "_"+Bake.options.build_config
          end
          file.write "digraph \"#{starting}#{ending}\" {\n\n"

          file.write "  concentrate = true\n\n"

          if onlyProjectName
            if not @referencedConfigs.include? onlyProjectName
              Bake.formatter.printError("Error: project #{onlyProjectName} not found")
              ExitHelper.exit(1)
            end
            if onlyConfigName
              if not @referencedConfigs[onlyProjectName].any? {|c| c.name == onlyConfigName}
                Bake.formatter.printError("Error: project #{onlyProjectName} with config #{onlyConfigName} not found")
                ExitHelper.exit(1)
              end
            end
          end

          foundProjs = {}
          @referencedConfigs.each do |projName, configs|
            depsToProj = []
            configs.each do |config|
              the_c = Blocks::ALL_BLOCKS[config.parent.name+","+config.name]
              the_c.besDirect.each do |d|
                next if Metamodel::IncludeDir === d
                if onlyProjectName
                  next if config.parent.name != onlyProjectName && d.name != onlyProjectName
                  if onlyConfigName
                    leftSide  = config.name        == onlyConfigName && config.parent.name == onlyProjectName
                    rightSide = d.config           == onlyConfigName && d.name             == onlyProjectName
                    next if !leftSide && !rightSide
                  end
                end
                if Bake.options.dotShowProjOnly
                  next if depsToProj.include?d.name
                  next if d.name == projName
                  c1 = ""
                  c2 = ""
                else
                  c1 = ",#{config.name}"
                  c2 = ",#{d.config}"
                end
                file.write "  \"#{Blocks::ALL_BLOCKS[config.qname].projectDir}#{c1}\" -> "+
                  "\"#{Blocks::ALL_BLOCKS[d.name+','+d.config].projectDir}#{c2}\"\n"
                depsToProj << d.name

                foundProjs[config.parent.name] = []           if not foundProjs.include? config.parent.name
                foundProjs[config.parent.name] << config.name if not foundProjs[config.parent.name].include? config.name
                foundProjs[d.name] = []        if not foundProjs.include? d.name
                foundProjs[d.name] << d.config if not foundProjs[d.name].include? d.config
              end
            end
          end
          file.write "\n"

          if Bake.options.dotShowProjOnly
            @referencedConfigs.each do |projName, configs|
              next if Bake.options.project and not foundProjs.include?projName
              file.write "  \"#{Blocks::ALL_BLOCKS[configs[0].qname].projectDir}\" [label = \"#{projName}\"]\n"
            end
          else
            @referencedConfigs.each do |projName, configs|
              next if Bake.options.project and not foundProjs.include?projName
              dirName = Blocks::ALL_BLOCKS[configs[0].qname].projectDir
              file.write "  subgraph \"cluster_#{dirName}\" {\n"
              file.write "    label =\"#{projName}\"\n"
              configs.each do |config|
                next if Bake.options.project and not foundProjs[projName].include? config.name
                file.write "    \"#{dirName},#{config.name}\" [label = \"#{config.name}\", style =  filled, fillcolor = #{config.color}]\n"
              end
              file.write "  }\n\n"
            end
          end

          file.write "}\n"
        end

        ExitHelper.exit(0) if !Bake.options.dotAndCompile
    end

    def convert2bb
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          block = Blocks::ALL_BLOCKS[config.qname]

          addSteps(block, block.startupSteps,  config.startupSteps)
          addSteps(block, block.exitSteps,  config.exitSteps)

          if not Bake.options.prepro and not Bake.options.conversion_info and not Bake.options.docu and not Bake.options.filename and not Bake.options.analyze
            if block.prebuild
              addLib(block, config.preSteps)
              addLib(block, config.postSteps)
              addLib(block, config.cleanSteps)
            else
              addSteps(block, block.preSteps,   config.preSteps)
              addSteps(block, block.postSteps,  config.postSteps)
              addSteps(block, block.cleanSteps, config.cleanSteps)
            end
          end

          if Bake.options.docu
            block.mainSteps << Blocks::Docu.new(config, @configTcMap[config]) unless block.prebuild
          elsif Metamodel::CustomConfig === config
            if not Bake.options.prepro and not Bake.options.conversion_info and not Bake.options.docu and not Bake.options.filename and not Bake.options.analyze
              if block.prebuild
                addLib(block, config)
              else
                addSteps(block, block.mainSteps, config) if config.step
              end
            end
          elsif Bake.options.conversion_info
            block.mainSteps << Blocks::Convert.new(block, config, @referencedConfigs) unless block.prebuild
          else
            if not block.prebuild
              compile = Blocks::Compile.new(block, config, @referencedConfigs)
              (Blocks::ALL_COMPILE_BLOCKS[projName] ||= []) << compile
              block.mainSteps << compile
            end
            if not Bake.options.filename and not Bake.options.analyze
              if Metamodel::ExecutableConfig === config || (Bake.options.dev_features.include?("enforce-executable-config") && config == @mainConfig)
                block.mainSteps << Blocks::Executable.new(block, config, @referencedConfigs, compile) unless block.prebuild
              else
                block.mainSteps << Blocks::Library.new(block, config, @referencedConfigs, compile)
              end
            end
          end

        end
      end
    end

    def callBlock(block, method)
      begin
        return block.send(method)
      rescue AbortException
        raise
      rescue Exception => ex
        if Bake.options.debug
          puts ex.message
          puts ex.backtrace
        end
        return false
      end
    end

    def callBlocks(startBlocks, method, ignoreStopOnFirstError = false)
      Blocks::ALL_BLOCKS.each {|name,block| block.visited = false; block.result = true;  block.inDeps = false }
      Blocks::Block.reset_block_counter
      result = true
      startBlocks.each do |block|
        begin
          result = callBlock(block, method) && result
        ensure
          Blocks::Block::waitForAllThreads()
          result &&= Blocks::Block.delayed_result
        end
        if not ignoreStopOnFirstError
          return false if not result and Bake.options.stopOnFirstError
        end
      end
      return result
    end

    def calcStartBlocks
      startProjectName = nil
      startConfigName = nil
      if Bake.options.project
        splitted = Bake.options.project.split(',')
        startProjectName = splitted[0]
        startConfigName = splitted[1] if splitted.length == 2
      end

      if startConfigName
        blockName = startProjectName+","+startConfigName
        if not Blocks::ALL_BLOCKS.include?(startProjectName+","+startConfigName)
          Bake.formatter.printError("Error: project #{startProjectName} with config #{startConfigName} not found")
          ExitHelper.exit(1)
        end
        startBlocks = [Blocks::ALL_BLOCKS[startProjectName+","+startConfigName]]
        Blocks::Block.set_num_projects(startBlocks)
      elsif startProjectName
        startBlocks = []
        Blocks::ALL_BLOCKS.each do |blockName, block|
          if blockName.start_with?(startProjectName + ",")
            startBlocks << block
          end
        end
        if startBlocks.length == 0
          Bake.formatter.printError("Error: project #{startProjectName} not found")
          ExitHelper.exit(1)
        end
        startBlocks.reverse! # most probably the order of dependencies if any
        Blocks::Block.set_num_projects(startBlocks)
      else
        startBlocks = [Blocks::ALL_BLOCKS[Bake.options.main_project_name+","+Bake.options.build_config]]
        Blocks::Block.set_num_projects(Blocks::ALL_BLOCKS.values)
      end
     return startBlocks
    end

    def doit()

      stdoutSuppression = nil
      orgStdout = nil
      if Bake.options.show_includes || Bake.options.show_includes_and_defines
        stdoutSuppression = StringIO.new
        orgStdout = Thread.current[:stdout]
        Thread.current[:stdout] = stdoutSuppression unless orgStdout
      end

      begin

        taskType = "Building"
        if Bake.options.conversion_info
          taskType = "Showing conversion infos"
        elsif Bake.options.docu
          taskType = "Generating documentation"
        elsif Bake.options.prepro
          taskType = "Preprocessing"
        elsif Bake.options.linkOnly
            taskType = "Linking"
        elsif Bake.options.rebuild
          taskType = "Rebuilding"
        elsif Bake.options.clean
          taskType = "Cleaning"
        end

        begin

          if Bake.options.showConfigs
            al = AdaptConfig.new
            adaptConfigs = al.load()
            Config.new.printConfigs(adaptConfigs)
          else
            cache = CacheAccess.new()
            @referencedConfigs = cache.load_cache unless Bake.options.nocache

            if @referencedConfigs.nil?
              al = AdaptConfig.new
              adaptConfigs = al.load()

              @loadedConfig = Config.new
              @referencedConfigs = @loadedConfig.load(adaptConfigs)

              cache.write_cache(@referencedConfigs, adaptConfigs)
            end
          end

          taskType = "Analyzing" if Bake.options.analyze

          @mainConfig = @referencedConfigs[Bake.options.main_project_name].select { |c| c.name == Bake.options.build_config }.first

          basedOn =  @mainConfig.defaultToolchain.basedOn
          basedOnToolchain = Bake::Toolchain::Provider[basedOn]
          if basedOnToolchain.nil?
            Bake.formatter.printError("DefaultToolchain based on unknown compiler '#{basedOn}'", @mainConfig.defaultToolchain)
            ExitHelper.exit(1)
          end

          # The flag "-FS" must only be set for VS2013 and above
          ENV["MSVC_FORCE_SYNC_PDB_WRITES"] = ""
          if basedOn == "MSVC"
            begin
              res = `cl.exe 2>&1`
              raise Exception.new unless $?.success?
              scan_res = res.scan(/ersion (\d+).(\d+).(\d+)/)
              if scan_res.length > 0
                ENV["MSVC_FORCE_SYNC_PDB_WRITES"] = "-FS" if scan_res[0][0].to_i >= 18 # 18 is the compiler major version in VS2013
              else
                Bake.formatter.printError("Could not read MSVC version")
                ExitHelper.exit(1)
              end
            rescue SystemExit
              raise
            rescue Exception => e
              Bake.formatter.printError("Could not detect MSVC compiler")
              ExitHelper.exit(1)
            end
          end

          @defaultToolchain = Utils.deep_copy(basedOnToolchain)
          @defaultToolchain = fill_compiler_env(@defaultToolchain)
    
          integrateToolchain(@defaultToolchain, @mainConfig.defaultToolchain)

          # todo: cleanup this hack
          Bake.options.analyze = @defaultToolchain[:COMPILER][:CPP][:COMPILE_FLAGS].include?"analyze"
          Bake.options.eclipseOrder = @mainConfig.defaultToolchain.eclipseOrder

          puts "Profiling #{Time.now - $timeStart}: create base toolchains..." if Bake.options.profiling
          createBaseTcsForConfig
          puts "Profiling #{Time.now - $timeStart}: substitute variables..." if Bake.options.profiling
          substVars
          puts "Profiling #{Time.now - $timeStart}: toolchains..." if Bake.options.profiling
          createTcsForConfig
          @@linkBlock = 0
          @prebuild = nil
          if Bake.options.prebuild
            puts "Profiling #{Time.now - $timeStart}: create prebuild blocks..." if Bake.options.profiling
            calcPrebuildBlocks
          end
          puts "Profiling #{Time.now - $timeStart}: make blocks..." if Bake.options.profiling
          makeBlocks
          puts "Profiling #{Time.now - $timeStart}: make graph..." if Bake.options.profiling
          makeGraph
          puts "Profiling #{Time.now - $timeStart}: make includes..." if Bake.options.profiling
          makeIncs
          puts "Profiling #{Time.now - $timeStart}: make dep overview..." if Bake.options.profiling
          makeDepOverview
          puts "Profiling #{Time.now - $timeStart}: make uniq..." if Bake.options.profiling
          makeUniq
          puts "Profiling #{Time.now - $timeStart}: convert to building blocks..." if Bake.options.profiling
          convert2bb
          if Bake.options.dot
            puts "Profiling #{Time.now - $timeStart}: make dot..." if Bake.options.profiling
            makeDot
          end

          if !Bake.options.cc2j_filename
            if !@mainConfig.cdb.nil?
              Bake.options.cc2j_filename = @mainConfig.cdb.name
              if !File.is_absolute?(Bake.options.cc2j_filename)
                Bake.options.cc2j_filename = File.join(
                  File.rel_from_to_project(Dir.pwd, @mainConfig.parent.get_project_dir, false),
                  Bake.options.cc2j_filename)
              end
            end
          end

          metadata_json = Bake.options.dev_features.detect { |x| x.start_with?("metadata=") }
          if metadata_json
            metadata_file = metadata_json[9..-1]
            mainBlock = Blocks::ALL_BLOCKS[@mainConfig.parent.name + "," + @mainConfig.name]
            if Metamodel::ExecutableConfig === mainBlock.config || Metamodel::LibraryConfig === mainBlock.config
              Subst.substToolchain(@defaultToolchain)
              File.open(metadata_file, "w") do |f|
                f.puts "{"
                f.puts "  \"module_path\":  \"#{mainBlock.projectDir}\","
                f.puts "  \"config_name\":  \"#{@mainConfig.name}\","
                Dir.chdir(mainBlock.projectDir) do
                  if Blocks::Library === mainBlock.mainSteps.last || Blocks::Executable === mainBlock.mainSteps.last
                    aName = File.expand_path(mainBlock.mainSteps.last.calcArtifactName)
                  else
                    aName = ""
                  end
                  f.puts "  \"artifact\":     \"#{aName}\","
                end
                f.puts "  \"compiler_c\":   \"#{@defaultToolchain[:COMPILER][:C][:COMMAND]}\","
                f.puts "  \"compiler_cxx\": \"#{@defaultToolchain[:COMPILER][:CPP][:COMMAND]}\","
                f.puts "  \"flags_c\":      \"#{@defaultToolchain[:COMPILER][:C][:FLAGS]}\","
                f.puts "  \"flags_cxx\":    \"#{@defaultToolchain[:COMPILER][:CPP][:FLAGS]}\","
                f.puts "  \"toolchain\":    \"#{@mainConfig.defaultToolchain.basedOn}\""
                f.puts "}"
              end
              puts "File #{metadata_file} written."
              ExitHelper.exit(0)
            else
              Bake.formatter.printError("Error: dev-feature metadata is only for LibraryConfig or ExecutableConfig.")
              ExitHelper.exit(1)
            end
          end

        ensure
          if Bake.options.show_includes || Bake.options.show_includes_and_defines
            Thread.current[:stdout] = orgStdout
            puts stdoutSuppression.string # this ensures to print a error message is needed even in case of an exception
          end
        end

        if Bake.options.show_includes
          Blocks::Show.includes
        end

        if Bake.options.show_includes_and_defines
          Blocks::Show.includesAndDefines(@mainConfig, @configTcMap[@mainConfig])
        end

        startBlocks = calcStartBlocks

        Bake::IDEInterface.instance.set_build_info(@mainConfig.parent.name, @mainConfig.name, Blocks::ALL_BLOCKS.length)

        ideAbort = false
        Blocks::Block.reset_delayed_result

        puts "Profiling #{Time.now - $timeStart}: start build..." if Bake.options.profiling

        begin
          Blocks::Block.init_threads()
          result = callBlocks(startBlocks, :startup, true)
          if Bake.options.clean or Bake.options.rebuild
            if not Bake.options.stopOnFirstError or result
              result = callBlocks(startBlocks, :clean) && result
            end
          end
          if Bake.options.rebuild or not Bake.options.clean
            if not Bake.options.stopOnFirstError or result
              result = callBlocks(startBlocks, :execute) && result
            end
          end
        rescue AbortException
          ideAbort = true
        end
        result = callBlocks(startBlocks, :exits, true) && result

        if ideAbort || Bake::IDEInterface.instance.get_abort
          Bake.formatter.printError("\n#{taskType} aborted.")
          ExitHelper.set_exit_code(1)
          return
        end

        if Bake.options.cc2j_filename
          require "json"
          begin 
            Bake.formatter.printInfo("Info: writing compilation database #{Bake.options.cc2j_filename}") if Bake.options.verbose >= 1
            File.write(Bake.options.cc2j_filename, JSON.pretty_generate(Blocks::CC2J))
          rescue Exception => ex
            Bake.formatter.printError("Error: could not write compilation database: #{ex.message}")
            puts ex.backtrace if Bake.options.debug
            result = false
          end
        end

        if Bake.options.filelist && !Bake.options.dry
          mainBlock = Blocks::ALL_BLOCKS[Bake.options.main_project_name+","+Bake.options.build_config]
          Dir.chdir(mainBlock.projectDir) do
            Utils.gitIgnore(mainBlock.output_dir)
            File.open(mainBlock.output_dir + "/" + "global-file-list.txt", 'wb') do |f|
              Bake.options.filelist.sort.each do |entry|
                f.puts(entry)
              end
            end
          end
        end

        if result == false
          Bake.formatter.printError("\n#{taskType} failed.")
          ExitHelper.set_exit_code(1)
          return
        else
          if Bake.options.linkOnly and @@linkBlock == 0
            Bake.formatter.printSuccess("\nNothing to link.")
          else
            # CompilationCheck
            if !Bake.options.project &&
               !Bake.options.filename &&
               !Bake.options.linkOnly &&
               !Bake.options.prepro &&
               !Bake.options.compileOnly &&
               !Bake.options.clean

              ccChecks = []
              ccIncludes = Set.new
              ccExcludes = Set.new
              ccIgnores = Set.new
              @referencedConfigs.each do |projName, configs|
                configs.compilationCheck.each do |cc|
                  ccChecks << cc
                end
              end
              ccChecks.each do |cc|
                Dir.chdir(cc.parent.parent.get_project_dir) do
                  Dir.glob(cc.include).select {|f| File.file?(f)}.each {|f| ccIncludes << File.expand_path(f)}
                  Dir.glob(cc.exclude).select {|f| File.file?(f)}.each {|f| ccExcludes << File.expand_path(f)}
                  Dir.glob(cc.ignore). select {|f| File.file?(f)}.each {|f| ccIgnores  << File.expand_path(f)}
                end
              end
              ccIncludes -= ccIgnores
              ccExcludes -= ccIgnores
              ccIncludes -= ccExcludes

              if !ccIncludes.empty? || !ccExcludes.empty?
                inCompilation = Set.new
                Blocks::ALL_BLOCKS.each do |name,block|
                  block.mainSteps.each do |b|
                    if Blocks::Compile === b && !b.source_files_compiled.nil?
                      b.source_files_compiled.each do |s|
                        inCompilation << File.expand_path(s, b.projectDir)
                        type = b.get_source_type(s)
                        if type != :ASM && b.object_files && b.object_files.has_key?(s)
                          o = b.object_files[s]
                          dep_filename = b.calcDepFile(o, type)
                          dep_filename_conv = b.calcDepFileConv(dep_filename)
                          File.readlines(File.expand_path(dep_filename_conv, b.projectDir)).map{|line| line.strip}.each do |dep|
                            header = File.expand_path(dep, b.projectDir)
                            if File.exist?(header)
                              inCompilation << header
                            end
                          end
                        end
                      end
                    end
                  end
                end

                pnPwd = Pathname.new(Dir.pwd)
                ccNotIncluded = (ccIncludes - inCompilation).to_a
                ccNotExcluded = inCompilation.select {|i| ccExcludes.include?(i) }
                ccNotIncluded.each do |cc|
                  cc = Pathname.new(cc).relative_path_from(pnPwd)
                  Bake.formatter.printWarning("Warning: file not included in build: #{cc}")
                end
                ccNotExcluded.each do |cc|
                  cc = Pathname.new(cc).relative_path_from(pnPwd)
                  Bake.formatter.printWarning("Warning: file not excluded from build: #{cc}")
                end

                if Bake.options.verbose >= 3
                  if ccNotIncluded.empty? && ccNotExcluded.empty?
                    Bake.formatter.printInfo("Info: CompilationCheck passed")
                  end
                end

              elsif !ccChecks.empty?
                if Bake.options.verbose >= 3
                  Bake.formatter.printInfo("Info: CompilationCheck passed")
                end
              end
            end
            
            
            Bake.formatter.printSuccess("\n#{taskType} done.")
          end
        end
      rescue SystemExit
        Bake.formatter.printError("\n#{taskType} failed.") if ExitHelper.exit_code != 0
      end

    end

    def connect()
      if Bake.options.socket != 0
        Bake::IDEInterface.instance.connect(Bake.options.socket)
      end
    end

    def disconnect()
      if Bake.options.socket != 0
        Bake::IDEInterface.instance.disconnect()
      end
    end

  end
end

trap("SIGINT") do
  Bake::IDEInterface.instance.set_abort(1)
end