#!/usr/bin/python3
import os
import sys
import subprocess

SM_INCLUDES = "includes"
SPCOMP = "./spcomp"

if __name__ == "__main__":
	Plugins = []
	Path, Directories, Files = next(os.walk("."))
	for Directory in Directories:
		if Directory != ".git" and Directory != "include" and Directory != "includes" and Directory != "plugins":
			Plugins.append(Directory)

	for Plugin in Plugins:
		print("Compiling {0}".format(Plugin))

		SourcePath = os.path.join(Plugin, "scripting")
		Path, Directories, Files = next(os.walk(SourcePath))
		for File in Files:
			if File.endswith(".sp"):
				SourcePath = os.path.join(Path, File)
				IncludePath = os.path.join(Path, "include")
				OutDir = "plugins"
				OutPath = os.path.join(OutDir, os.path.splitext(os.path.basename(SourcePath))[0] + ".smx")

				Compiler = [SPCOMP, "-i" + SM_INCLUDES]
				if os.path.isdir(IncludePath):
					Compiler.append("-i" + IncludePath)
				Compiler.append(SourcePath)
				Compiler.append("-o" + OutPath)

				try:
					subprocess.run(Compiler, check=True)
				except Exception:
					sys.exit(1)
