# User request

The user provided this release failure log.

```text
........................................................................
created: /Users/gabe/projects.next/Schnap/build/releases/0.7.11-beta.2/Schnaps-0.7.11-beta.2.dmg
hdiutil: WARNING: 'hdiutil create -volname -format ...' is deprecated. Please use 'diskutil image create from/blank --volumeName --format ...' instead.
/Users/gabe/projects.next/Schnap/build/releases/0.7.11-beta.2/Schnaps-0.7.11-beta.2.dmg: A timestamp was expected but was not found.
Swift/ErrorType.swift:254: Fatal error: Error raised at top level: Error Domain=/usr/bin/codesign Code=1 "(null)"
Stack dump:
0.      Program arguments: /Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend -frontend -interpret Scripts/release.swift -Xllvm -aarch64-use-tbi -enable-objc-interop -stack-check -sdk /Applications/Xcode-26.6.0.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -color-diagnostics -Xcc -fcolor-diagnostics -new-driver-path /Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-driver -empty-abi-descriptor -no-auto-bridging-header-chaining -module-name release -disable-clang-spi -target-sdk-version 26.5 -target-sdk-name macosx26.5 -external-plugin-path /Applications/Xcode-26.6.0.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins#/Applications/Xcode-26.6.0.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/bin/swift-plugin-server -external-plugin-path /Applications/Xcode-26.6.0.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/local/lib/swift/host/plugins#/Applications/Xcode-26.6.0.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/bin/swift-plugin-server -in-process-plugin-server-path /Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/libSwiftInProcPluginServer.dylib -plugin-path /Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins -plugin-path /Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/local/lib/swift/host/plugins
1.      Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
2.      Compiling with effective version 5.10
3.      While running user code "Scripts/release.swift"
Stack dump without symbol names (ensure you have llvm-symbolizer in your PATH or set the environment var `LLVM_SYMBOLIZER_PATH` to point to it):
0  swift-frontend           0x00000001090c108c llvm::sys::PrintStackTrace(llvm::raw_ostream&, int) + 56
1  swift-frontend           0x00000001090be52c llvm::sys::RunSignalHandlers() + 172
2  swift-frontend           0x00000001090c167c SignalHandler(int, __siginfo*, void*) + 356
3  libsystem_platform.dylib 0x0000000187cae144 _sigtramp + 56
4  libswiftCore.dylib       0x0000000182ee1604 $ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_SSAHSus6UInt32VtF + 180
5  libswiftCore.dylib       0x0000000182dc0898 swift_errorInMain + 632
6  (error)                  0x000000011660f08c
7  swift-frontend           0x0000000102db4c48 llvm::orc::runAsMain(int (*)(int, char**), llvm::ArrayRef<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>, std::__1::optional<llvm::StringRef>) + 908
8  swift-frontend           0x0000000102cb1f94 swift::SwiftJIT::runMain(llvm::ArrayRef<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>) + 636
9  swift-frontend           0x0000000102cbe23c swift::RunImmediately(swift::CompilerInstance&, std::__1::vector<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>, std::__1::allocator<std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>>> const&, swift::IRGenOptions const&, swift::SILOptions const&, std::__1::unique_ptr<swift::SILModule, std::__1::default_delete<swift::SILModule>>&&) + 964
10 swift-frontend           0x0000000102c320d0 processCommandLineAndRunImmediately(swift::CompilerInstance&, std::__1::unique_ptr<swift::SILModule, std::__1::default_delete<swift::SILModule>>&&, llvm::PointerUnion<swift::ModuleDecl*, swift::SourceFile*>, swift::FrontendObserver*, int&) + 484
11 swift-frontend           0x0000000102c2b89c performCompileStepsPostSILGen(swift::CompilerInstance&, std::__1::unique_ptr<swift::SILModule, std::__1::default_delete<swift::SILModule>>, llvm::PointerUnion<swift::ModuleDecl*, swift::SourceFile*>, swift::PrimarySpecificPaths const&, int&, swift::FrontendObserver*, llvm::ArrayRef<char const*>) + 2068
12 swift-frontend           0x0000000102c2aecc swift::performCompileStepsPostSema(swift::CompilerInstance&, int&, swift::FrontendObserver*, llvm::ArrayRef<char const*>) + 4560
13 swift-frontend           0x0000000102c303a0 performCompile(swift::CompilerInstance&, int&, swift::FrontendObserver*, llvm::ArrayRef<char const*>) + 4028
14 swift-frontend           0x0000000102c2c818 swift::performFrontend(llvm::ArrayRef<char const*>, char const*, void*, swift::FrontendObserver*) + 3308
15 swift-frontend           0x0000000102bac424 swift::mainEntry(int, char const**) + 5224
16 dyld                     0x0000000182c10d7c start + 6652
Release failed: swift failed (5).
make: *** [beta] Error 1
```

# Delegated PR monitoring prompt

Monitor the open PR for branch codex/gabriel/retry-release-dmg-timestamp in rel-me/Schnaps through completion of both macOS Swift jobs on the latest head. Use the shared worktree at /Users/gabe/.codex/worktrees/6955/Schnap. The change retries DMG signing for Apple secure timestamp errors and reports packaging failures without a Swift stack dump. Investigate failures and fix those caused by this PR. Run relevant tests, commit and push any fixes, and monitor the updated head. Preserve unrelated changes and leave the PR open. Report the verified head and check outcomes or any concrete blocker.
