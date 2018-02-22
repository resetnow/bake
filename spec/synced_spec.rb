#!/usr/bin/env ruby

require 'helper'

require 'common/version'

require 'bake/options/options'
require 'bake/util'
require 'common/exit_helper'
require 'socket'
require 'fileutils'

require 'common/ext/stdout'

module Bake

describe "Synced" do

  it 'Passing build without -r' do
    Bake.startBake("synced/main", ["test_exe1", "-O"])
    posLib = $mystring.rindex("(test_lib1)")
    posExe = $mystring.index("(test_exe1)")
    expect(posLib<posExe).to be == true
    expect($mystring.include?("Building done.")).to be == true
    expect(ExitHelper.exit_code).to be == 0
  end

  it 'Passing build with -r' do
    Bake.startBake("synced/main", ["test_exe1", "-O", "-r"])
    posLib = $mystring.rindex("(test_lib1)")
    posExe = $mystring.index("(test_exe1)")
    expect(posLib<posExe).to be == true
    expect($mystring.include?("Building done.")).to be == true
    expect(ExitHelper.exit_code).to be == 0
  end

  it 'Broken build without -r' do
    Bake.startBake("synced/main", ["test_exe2", "-O", "-r"])

    posError = $mystring.index ("src/lib2/f1.o")
    posLib2A = $mystring.index ("(test_lib2)")
    posLib2B = $mystring.rindex("(test_lib2)")
    posLib1A = $mystring.index ("(test_lib1)")
    posLib1B = $mystring.rindex("(test_lib1)")
    posExeA = $mystring.index  ("(test_exe2)")
    posExeB = $mystring.rindex ("(test_exe2)")

    if (posLib1A && posLib2A)
      expect((posLib1A > posLib2B && posLib1B > posLib2B) || (posLib1A < posLib2A && posLib1B < posLib2A)).to be == true
    end
    if (posExeA && posLib2A)
      expect((posExeA > posLib2B && posExeB > posLib2B) || (posExeA < posLib2A && posExeB < posLib2A)).to be == true
    end
    if (posExeA && posLib1A)
      expect((posLib1A > posExeB && posLib1B > posExeB) || (posLib1A < posExeA && posLib1B < posExeA)).to be == true
    end

    expect(posError > 0).to be == true
  end

  it 'Broken build with -r' do
    Bake.startBake("synced/main", ["test_exe2", "-O", "-r"])

    posError = $mystring.index ("src/lib2/f1.o")
    posLib2A = $mystring.index ("(test_lib2)")
    posLib2B = $mystring.rindex("(test_lib2)")
    posLib1A = $mystring.index ("(test_lib1)")
    posLib1B = $mystring.rindex("(test_lib1)")
    posExeA = $mystring.index  ("(test_exe2)")
    posExeB = $mystring.rindex ("(test_exe2)")

    if (posLib1A && posLib2A)
      expect((posLib1A > posLib2B && posLib1B > posLib2B) || (posLib1A < posLib2A && posLib1B < posLib2A)).to be == true
    end
    if (posExeA && posLib2A)
      expect((posExeA > posLib2B && posExeB > posLib2B) || (posExeA < posLib2A && posExeB < posLib2A)).to be == true
    end
    if (posExeA && posLib1A)
      expect((posLib1A > posExeB && posLib1B > posExeB) || (posLib1A < posExeA && posLib1B < posExeA)).to be == true
    end
    expect(posError > 0).to be == true
  end


  it 'Broken build with -r and -j 1' do
    Bake.startBake("synced/main", ["test_exe2", "-O", "-r", "-j", "1"])

    posError = $mystring.index ("src/lib2/f1.o")
    posLib2A = $mystring.index ("(test_lib2)")
    posLib2B = $mystring.rindex("(test_lib2)")
    posLib1A = $mystring.index ("(test_lib1)")
    posExeA = $mystring.index  ("(test_exe2)")

    expect(posLib1A.nil?).to be == true
    expect(posExeA.nil?).to be == true
    expect(posError > 0).to be == true
  end

  it 'Prestep error without -r' do
    Bake.startBake("synced/main", ["test_exe3", "-O"])

    posLib1A = $mystring.index ("(test_lib1)")
    posLib1B = $mystring.rindex("(test_lib1)")
    posPreA = $mystring.index ("(test_pre")
    posPreB = $mystring.rindex("(test_pre")
    posError = $mystring.index ("really_broken")
    posExeA = $mystring.index  ("(test_exe3)")
    posExeB = $mystring.rindex ("(test_exe3)")

    expect(posError > 0).to be == true
  end

  it 'Prestep error with -r' do
    Bake.startBake("synced/main", ["test_exe3", "-O", "-r"])

    posLib1A = $mystring.index ("(test_lib1)")
    posLib1B = $mystring.rindex("(test_lib1)")
    posPreA = $mystring.index ("(test_pre")
    posPreB = $mystring.rindex("(test_pre")
    posError = $mystring.index ("really_broken")
    posExeA = $mystring.index  ("(test_exe3)")
    posExeB = $mystring.rindex ("(test_exe3)")

    expect(posError > 0).to be == true
    expect(posExeA.nil?).to be == true
  end

end

end
