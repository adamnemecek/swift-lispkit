//
//  SystemLibrary.swift
//  LispKit
//
//  Created by Matthias Zenger on 10/12/2016.
//  Copyright © 2016, 2017 ObjectHub. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

public final class SystemLibrary: NativeLibrary {
  
  /// Container for the current directory path parameter.
  private var currentDirectoryProc: Procedure!
  private var compileAndEvalFirstProc: Procedure!
  
  public var currentDirectoryPath: String {
    get {
      do {
        return try self.context.machine.getParam(self.currentDirectoryProc)!.asString()
      } catch {
        preconditionFailure("current directory path not a string")
      }
    }
    set {
      _ = self.context.machine.setParam(self.currentDirectoryProc, to: .makeString(newValue))
    }
  }
  
  /// Name of the library.
  public override class var name: [String] {
    return ["lispkit", "system"]
  }
  
  /// Dependencies of the library.
  public override func dependencies() {
  }
  
  /// Declarations of the library.
  public override func declarations() {
    self.currentDirectoryProc =
      Procedure(.procedure(Procedure("_validCurrentPath", self.validCurrentPath)),
                .makeString(self.context.fileHandler.currentDirectoryPath))
    self.compileAndEvalFirstProc =
      Procedure("_compileAndEvalFirst", self.compileAndEvalFirst)
    self.define("current-directory", as: .procedure(self.currentDirectoryProc))
    self.define(Procedure("file-path", self.filePath))
    self.define(Procedure("parent-file-path", self.parentFilePath))
    self.define(Procedure("file-path-root?", self.filePathRoot))
    self.define(Procedure("load", self.load))
    self.define(Procedure("file-exists?", self.fileExists))
    self.define(Procedure("directory-exists?", self.directoryExists))
    self.define(Procedure("file-or-directory-exists?", self.fileOrDirectoryExists))
    self.define(Procedure("delete-file", self.deleteFile))
    self.define(Procedure("delete-directory", self.deleteDirectory))
    self.define(Procedure("delete-file-or-directory", self.deleteFileOrDirectory))
    self.define(Procedure("copy-file", self.copyFile))
    self.define(Procedure("copy-directory", self.copyDirectory))
    self.define(Procedure("copy-file-or-directory", self.copyFileOrDirectory))
    self.define(Procedure("move-file", self.copyFile))
    self.define(Procedure("move-directory", self.copyDirectory))
    self.define(Procedure("move-file-or-directory", self.copyFileOrDirectory))
    self.define(Procedure("file-size", self.fileSize))
    self.define(Procedure("directory-list", self.directoryList))
    self.define(Procedure("make-directory", self.makeDirectory))
    self.define(Procedure("get-environment-variable", self.getEnvironmentVariable))
    self.define(Procedure("get-environment-variables", self.getEnvironmentVariables))
    self.define(Procedure("command-line", self.commandLine))
    self.define(Procedure("gc", self.gc))
    self.define(Procedure("compile", self.compile))
    self.define(Procedure("disassemble", self.disassemble))
    self.define(Procedure("available-symbols", self.availableSymbols))
    self.define(Procedure("loaded-libraries", self.loadedLibraries))
    self.define(Procedure("environment-info", self.environmentInfo))
    self.define("time", as: SpecialForm(self.compileTime))
    self.define(Procedure("seconds-from-gmt", self.secondsFromGmt))
    self.define(Procedure("current-second", self.currentSecond))
    self.define(Procedure("current-jiffy", self.currentJiffy))
    self.define(Procedure("jiffies-per-second", self.jiffiesPerSecond))
    self.define(Procedure("features", self.features))
    self.define(Procedure("implementation-name", self.implementationName))
    self.define(Procedure("implementation-version", self.implementationVersion))
    self.define(Procedure("cpu-architecture", self.cpuArchitecture))
    self.define(Procedure("machine-name", self.machineName))
    self.define(Procedure("machine-model", self.machineModel))
    self.define(Procedure("os-type", self.osType))
    self.define(Procedure("os-version", self.osVersion))
    self.define(Procedure("os-name", self.osName))
    self.define(Procedure("os-release", self.osRelease))
  }
  
  private func filePath(expr: Expr, base: Expr?) throws -> Expr {
    var root = self.currentDirectoryPath
    if let base = try base?.asPath() {
      root = self.context.fileHandler.path(base, relativeTo: self.currentDirectoryPath)
    }
    return .makeString(self.context.fileHandler.path(try expr.asString(), relativeTo: root))
  }
  
  private func parentFilePath(expr: Expr) throws -> Expr {
    return .makeString(
      self.context.fileHandler.directory(try expr.asString(),
                                         relativeTo: self.currentDirectoryPath))
  }
  
  private func filePathRoot(expr: Expr) throws -> Expr {
    return .makeBoolean(
      self.context.fileHandler.path(try expr.asString(),
                                    relativeTo: self.currentDirectoryPath) == "/")
  }
  
  private func load(args: Arguments) throws -> (Procedure, [Expr]) {
    guard args.count == 1 || args.count == 2  else {
      throw EvalError.argumentCountError(formals: 2, args: .makeList(args))
    }
    // Extract arguments
    let path = try args.first!.asPath()
    let filename =
      self.context.fileHandler.filePath(forFile: path,
                                        relativeTo: self.currentDirectoryPath) ??
      self.context.fileHandler.libraryFilePath(forFile: path,
                                               relativeTo: self.currentDirectoryPath) ??
      self.context.fileHandler.path(path, relativeTo: self.currentDirectoryPath)
    var environment = self.context.environment
    if args.count == 2 {
      environment = try args[args.startIndex + 1].asEnvironment()
    }
    // Load file and parse expressions
    let exprs = try self.context.machine.parse(file: filename)
    let sourceDir = self.context.fileHandler.directory(filename)
    // Hand over work to `compileAndEvalFirst`
    return (self.compileAndEvalFirstProc, [exprs, .makeString(sourceDir), .env(environment!)])
  }
  
  private func compileAndEvalFirst(args: Arguments) throws -> (Procedure, [Expr]) {
    guard args.count == 3 else {
      throw EvalError.argumentCountError(formals: 3, args: .makeList(args))
    }
    let sourceDir = args[args.startIndex + 1]
    let env = args[args.startIndex + 2]
    switch args.first! {
      case .null:
        return (BaseLibrary.voidProc, [])
      case .pair(let expr, let rest):
        let source = Expr.pair(
          expr,
          .pair(.makeList(.procedure(self.compileAndEvalFirstProc),
                          .makeList(.symbol(Symbol(self.context.symbols.quote,
                                                   .global(self.context.environment))),
                                    rest),
                          sourceDir,
                          env),
                .null))
        let code = try Compiler.compile(expr: source,
                                        in: .global(try env.asEnvironment()),
                                        optimize: true,
                                        inDirectory: try sourceDir.asString())
        return (Procedure(code), [])
      default:
        throw EvalError.typeError(args.first!, [.properListType])
    }
  }
  
  private func validCurrentPath(param: Expr, expr: Expr, setter: Expr) throws -> Expr {
    self.currentDirectoryPath =
      self.context.fileHandler.path(try expr.asPath(),
                                    relativeTo: self.currentDirectoryPath)
    return .makeString(self.currentDirectoryPath)
  }
  
  private func fileExists(expr: Expr) throws -> Expr {
    return .makeBoolean(
      self.context.fileHandler.isFile(atPath: try expr.asPath(),
                                      relativeTo: self.currentDirectoryPath))
  }
  
  private func directoryExists(expr: Expr) throws -> Expr {
    return .makeBoolean(
      self.context.fileHandler.isDirectory(atPath: try expr.asPath(),
                                           relativeTo: self.currentDirectoryPath))
  }
  
  private func fileOrDirectoryExists(expr: Expr) throws -> Expr {
    return .makeBoolean(
      self.context.fileHandler.itemExists(atPath: try expr.asPath(),
                                          relativeTo: self.currentDirectoryPath))
  }
  
  private func deleteFile(expr: Expr) throws -> Expr {
    let path = try expr.asPath()
    if self.context.fileHandler.isFile(atPath: path,
                                       relativeTo: self.currentDirectoryPath) {
      try self.context.fileHandler.deleteItem(atPath: path,
                                              relativeTo: self.currentDirectoryPath)
      return .void
    } else {
      throw EvalError.unknownFile(path)
    }
  }
  
  private func deleteDirectory(expr: Expr) throws -> Expr {
    let path = try expr.asPath()
    if self.context.fileHandler.isDirectory(atPath: path,
                                            relativeTo: self.currentDirectoryPath) {
      try self.context.fileHandler.deleteItem(atPath: path,
                                              relativeTo: self.currentDirectoryPath)
      return .void
    } else {
      throw EvalError.unknownDirectory(path)
    }
  }
  
  private func deleteFileOrDirectory(expr: Expr) throws -> Expr {
    try self.context.fileHandler.deleteItem(atPath: try expr.asPath(),
                                            relativeTo: self.currentDirectoryPath)
    return .void
  }
  
  private func copyFile(fromPath: Expr, toPath: Expr) throws -> Expr {
    let path = try fromPath.asPath()
    if self.context.fileHandler.isFile(atPath: path,
                                       relativeTo: self.currentDirectoryPath) {
      try self.context.fileHandler.copyItem(atPath: path,
                                            toPath: try toPath.asPath(),
                                            relativeTo: self.currentDirectoryPath)
      return .void
    } else {
      throw EvalError.unknownFile(path)
    }
  }
  
  private func copyDirectory(fromPath: Expr, toPath: Expr) throws -> Expr {
    let path = try fromPath.asPath()
    if self.context.fileHandler.isDirectory(atPath: path,
                                            relativeTo: self.currentDirectoryPath) {
      try self.context.fileHandler.copyItem(atPath: path,
                                            toPath: try toPath.asPath(),
                                            relativeTo: self.currentDirectoryPath)
      return .void
    } else {
      throw EvalError.unknownDirectory(path)
    }
  }
  
  
  private func copyFileOrDirectory(fromPath: Expr, toPath: Expr) throws -> Expr {
    try self.context.fileHandler.copyItem(atPath: try fromPath.asPath(),
                                          toPath: try toPath.asPath(),
                                          relativeTo: self.currentDirectoryPath)
    return .void
  }
  
  private func moveFile(fromPath: Expr, toPath: Expr) throws -> Expr {
    let path = try fromPath.asPath()
    if self.context.fileHandler.isFile(atPath: path,
                                       relativeTo: self.currentDirectoryPath) {
      try self.context.fileHandler.moveItem(atPath: path,
                                            toPath: try toPath.asPath(),
                                            relativeTo: self.currentDirectoryPath)
      return .void
    } else {
      throw EvalError.unknownFile(path)
    }
  }
  
  private func moveDirectory(fromPath: Expr, toPath: Expr) throws -> Expr {
    let path = try fromPath.asPath()
    if self.context.fileHandler.isDirectory(atPath: path,
                                            relativeTo: self.currentDirectoryPath) {
      try self.context.fileHandler.moveItem(atPath: path,
                                            toPath: try toPath.asPath(),
                                            relativeTo: self.currentDirectoryPath)
      return .void
    } else {
      throw EvalError.unknownDirectory(path)
    }
  }
  
  
  private func moveFileOrDirectory(fromPath: Expr, toPath: Expr) throws -> Expr {
    try self.context.fileHandler.moveItem(atPath: try fromPath.asPath(),
                                          toPath: try toPath.asPath(),
                                          relativeTo: self.currentDirectoryPath)
    return .void
  }
  
  private func fileSize(expr: Expr) throws -> Expr {
    guard let size = self.context.fileHandler.fileSize(atPath: try expr.asPath(),
                                                       relativeTo: self.currentDirectoryPath) else {
      throw EvalError.unknownFile(try expr.asPath())
    }
    return .fixnum(size)
  }
  
  private func directoryList(expr: Expr) throws -> Expr {
    let contents = try self.context.fileHandler.contentsOfDirectory(
      atPath: try expr.asPath(), relativeTo: self.currentDirectoryPath)
    var res = Expr.null
    for item in contents {
      res = .pair(.makeString(item), res)
    }
    return res
  }
  
  private func makeDirectory(expr: Expr) throws -> Expr {
    try self.context.fileHandler.makeDirectory(atPath: try expr.asPath(),
                                               relativeTo: self.currentDirectoryPath)
    return .void
  }
  
  private func getEnvironmentVariable(expr: Expr) throws -> Expr {
    let name = try expr.asString()
    guard let value = ProcessInfo.processInfo.environment[name] else {
      return .false
    }
    return .makeString(value)
  }
  
  private func getEnvironmentVariables() -> Expr {
    var alist = Expr.null
    for (name, value) in ProcessInfo.processInfo.environment {
      alist = .pair(.pair(.makeString(name), .makeString(value)), alist)
    }
    return alist
  }
  
  private func commandLine() -> Expr {
    let args = CommandLine.arguments.reversed()
    var res = Expr.null
    for arg in args {
      res = .pair(.makeString(arg), res)
    }
    return res
  }
  
  private func gc() -> Expr {
    context.console.print("BEFORE: " + context.objects.description + "\n")
    let res = Expr.fixnum(Int64(self.context.objects.collectGarbage()))
    context.console.print("AFTER: " + context.objects.description + "\n")
    return res
  }
  
  private func compileTime(compiler: Compiler, expr: Expr, env: Env, tail: Bool) throws -> Bool {
    guard case .pair(_, .pair(let exec, .null)) = expr else {
      throw EvalError.argumentCountError(formals: 1, args: expr)
    }
    compiler.emit(.pushCurrentTime)
    try compiler.compile(exec, in: env, inTailPos: false)
    compiler.emit(.swap)
    compiler.emit(.pushCurrentTime)
    compiler.emit(.swap)
    compiler.emit(.flMinus)
    try compiler.pushValue(.makeString("elapsed time = "))
    compiler.emit(.display)
    compiler.emit(.display)
    compiler.emit(.newline)
    return false
  }
  
  private func compile(exprs: Arguments) throws -> Expr {
    var seq = Expr.null
    for expr in exprs.reversed() {
      seq = .pair(expr, seq)
    }
    let code = try Compiler.compile(expr: seq,
                                    in: self.context.global,
                                    optimize: true)
    context.console.print(code.description)
    return .void
  }
  
  private func disassemble(expr: Expr) throws -> Expr {
    guard case .procedure(let proc) = expr else {
      throw EvalError.typeError(expr, [.procedureType])
    }
    switch proc.kind {
    case .closure(_, let captured, let code):
      context.console.print(code.description)
      if captured.count > 0 {
        context.console.print("CAPTURED:\n")
        for i in captured.indices {
          context.console.print("  \(i): \(captured[i])\n")
        }
      }
    case .continuation(let vmState):
      context.console.print(vmState.description + "\n")
      context.console.print(vmState.registers.code.description)
      if vmState.registers.captured.count > 0 {
        context.console.print("CAPTURED:\n")
        for i in vmState.registers.captured.indices {
          context.console.print("  \(i): \(vmState.registers.captured[i])\n")
        }
      }
    default:
      context.console.print("cannot disassemble \(expr)\n")
    }
    return .void
  }
  
  private func availableSymbols() -> Expr {
    var res = Expr.null
    for sym in self.context.symbols {
      res = .pair(.symbol(sym), res)
    }
    return res
  }
  
  private func loadedLibraries() -> Expr {
    var res = Expr.null
    for library in self.context.libraries.loaded {
      res = .pair(library.name, res)
    }
    return res
  }
  
  private func environmentInfo() -> Expr {
    context.console.print("OBJECT SIZES\n")
    context.console.print("  atom size          : \(MemoryLayout<Expr>.size) bytes\n")
    context.console.print("  atom stride size   : \(MemoryLayout<Expr>.stride) bytes\n")
    context.console.print("  instr size         : \(MemoryLayout<Instruction>.size) bytes\n")
    context.console.print("  instr stride size  : \(MemoryLayout<Instruction>.stride) bytes\n")
    context.console.print("MANAGED OBJECT POOL\n")
    context.console.print("  tracked objects    : \(self.context.objects.numTrackedObjects)\n")
    context.console.print("  tracked capacity   : \(self.context.objects.trackedObjectCapacity)\n")
    context.console.print("  managed objects    : \(self.context.objects.numManagedObjects)\n")
    context.console.print("  managed capacity   : \(self.context.objects.managedObjectCapacity)\n")
    context.console.print("MANAGED OBJECT DISTRIBUTION\n")
    for (typeName, count) in self.context.objects.managedObjectDistribution {
      context.console.print("  \(typeName): \(count)\n")
    }
    context.console.print("GARBAGE COLLECTOR\n")
    context.console.print("  gc cycles          : \(self.context.objects.cycles)\n")
    context.console.print("  last tag           : \(self.context.objects.tag)\n")
    context.console.print("GLOBAL LOCATIONS\n")
    context.console.print("  allocated locations: \(self.context.heap.locations.count)\n")
    return .void
  }
  
  private func secondsFromGmt() -> Expr {
    return .fixnum(Int64(NSTimeZone.local.secondsFromGMT()))
  }
  
  private func currentSecond() -> Expr {
    var time = timeval(tv_sec: 0, tv_usec: 0)
    gettimeofday(&time, nil)
    return .flonum(Double(time.tv_sec) + (Double(time.tv_usec) / 1000000.0))
  }
  
  private func currentJiffy() -> Expr {
    var time = timeval(tv_sec: 0, tv_usec: 0)
    gettimeofday(&time, nil)
    return .fixnum(Int64(time.tv_sec) * 1000 + Int64(time.tv_usec / 1000))
  }
  
  private func jiffiesPerSecond() -> Expr {
    return .fixnum(1000)
  }
  
  private func features() -> Expr {
    var res: Expr = .null
    for feature in Feature.supported {
      res = .pair(.symbol(self.context.symbols.intern(feature.rawValue)), res)
    }
    return res
  }
  
  private func implementationName() -> Expr {
    if let name = self.context.implementationName {
      return .makeString(name)
    } else {
      return .false
    }
  }
  
  private func implementationVersion() -> Expr {
    if let version = self.context.implementationVersion {
      return .makeString(version)
    } else {
      return .false
    }
  }
  
  private func cpuArchitecture() -> Expr {
    return .makeString(Sysctl.machine)
  }
  
  private func machineName() -> Expr {
    return .makeString(Sysctl.hostName)
  }
  
  private func machineModel() -> Expr {
    return .makeString(Sysctl.model)
  }
  
  private func osType() -> Expr {
    return .makeString(Sysctl.osType)
  }
  
  private func osVersion() -> Expr {
    return .makeString(Sysctl.osVersion)
  }
  
  private func osName() -> Expr {
    #if os(macOS)
      return .makeString("macOS")
    #elseif os(iOS)
      return .makeString("iOS")
    #elseif os(Linux)
      return .makeString("Linux")
    #endif
  }
  
  private func osRelease() -> Expr {
    return .makeString("\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)." +
                       "\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)")
  }
}
