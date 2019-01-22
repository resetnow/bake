require_relative '../../common/utils'
require_relative '../toolchain/provider'
require_relative '../toolchain/errorparser/error_parser'
require_relative '../toolchain/errorparser/iar_compiler_error_parser'
require_relative '../toolchain/errorparser/iar_linker_error_parser'

module Bake
  module Toolchain

    IARChain = Provider.add("IAR")

    IARChain[:COMPILER][:CPP].update({
      :COMMAND => "armcc",
      :DEFINE_FLAG => "-D",
      :OBJECT_FILE_FLAG => "-o",
      :OBJ_FLAG_SPACE => true,
      :COMPILE_FLAGS => "-c ",
      :DEP_FLAGS => "--depend=",
      :DEP_FLAGS_SPACE => false,
      :PREPRO_FLAGS => "-E -P"
    })

    IARChain[:COMPILER][:C] = Utils.deep_copy(IARChain[:COMPILER][:CPP])
    IARChain[:COMPILER][:C][:SOURCE_FILE_ENDINGS] = Provider.default[:COMPILER][:C][:SOURCE_FILE_ENDINGS]

    IARChain[:COMPILER][:ASM] = Utils.deep_copy(IARChain[:COMPILER][:C])
    IARChain[:COMPILER][:ASM][:SOURCE_FILE_ENDINGS] = Provider.default[:COMPILER][:ASM][:SOURCE_FILE_ENDINGS]
    IARChain[:COMPILER][:ASM][:COMMAND] = "armasm"
    IARChain[:COMPILER][:ASM][:COMPILE_FLAGS] = ""
    IARChain[:COMPILER][:ASM][:PREFIX] = Provider.default[:COMPILER][:ASM][:PREFIX]

    IARChain[:COMPILER][:DEP_FILE_SINGLE_LINE] = true

    IARChain[:ARCHIVER][:COMMAND] = "armar"
    IARChain[:ARCHIVER][:ARCHIVE_FLAGS] = "--create"

    IARChain[:LINKER][:COMMAND] = "armlink"
    IARChain[:LINKER][:SCRIPT] = "--scatter"
    IARChain[:LINKER][:USER_LIB_FLAG] = ""
    IARChain[:LINKER][:EXE_FLAG] = "-o"
    IARChain[:LINKER][:LIB_FLAG] = ""
    IARChain[:LINKER][:LIB_PATH_FLAG] = "--userlibpath="
    IARChain[:LINKER][:MAP_FILE_FLAG] = "--map --list="
    IARChain[:LINKER][:MAP_FILE_PIPE] = false
    IARChain[:LINKER][:LIST_MODE] = true

    iarCompilerErrorParser =                   IARCompilerErrorParser.new
    IARChain[:COMPILER][:C][:ERROR_PARSER] =   iarCompilerErrorParser
    IARChain[:COMPILER][:CPP][:ERROR_PARSER] = iarCompilerErrorParser
    IARChain[:COMPILER][:ASM][:ERROR_PARSER] = iarCompilerErrorParser
    IARChain[:ARCHIVER][:ERROR_PARSER] =       iarCompilerErrorParser
    IARChain[:LINKER][:ERROR_PARSER] =         IARLinkerErrorParser.new

  end
end
