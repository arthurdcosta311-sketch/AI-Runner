//
//  ScriptRunner.swift
//  AI Runner
//

import Foundation
import JavaScriptCore

/// Runs the JavaScript and Lua a model writes, on the phone. JavaScript runs in
/// JavaScriptCore. Lua runs in the fengari VM bundled with the app, inside its own
/// JavaScriptCore context. Neither can reach the network or the file system.
enum ScriptRunner {
    static let timeoutSeconds: Double = 10

    static func javaScript(_ code: String) async -> String {
        await withTimeout { evaluateJavaScript(code) }
    }

    static func lua(_ code: String) async -> String {
        await withTimeout { evaluateLua(code) }
    }

    /// Runs the work off the main thread and gives up after the timeout, so a chat
    /// is never left waiting on a script that never ends.
    private static func withTimeout(_ work: @escaping () -> String) async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let lock = NSLock()
            var finished = false
            func finish(_ text: String) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(returning: text)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                finish(work())
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                finish("Error: the script was stopped after \(Int(timeoutSeconds)) seconds.")
            }
        }
    }

    private final class LogBuffer {
        var lines: [String] = []
        var error: String?
    }

    private static func evaluateJavaScript(_ code: String) -> String {
        guard let context = JSContext() else {
            return "Error: JavaScript is not available on this device."
        }
        let buffer = LogBuffer()
        let log: @convention(block) (JSValue) -> Void = { value in
            buffer.lines.append(value.toString() ?? "")
        }
        context.setObject(log, forKeyedSubscript: "__log" as NSString)
        context.exceptionHandler = { _, exception in
            buffer.error = exception?.toString()
        }
        context.evaluateScript("var console = {}; console.log = console.info = console.warn = console.error = function () { __log(Array.prototype.map.call(arguments, String).join(' ')); };")
        context.evaluateScript(code)
        if let error = buffer.error {
            buffer.lines.append("Error: \(error)")
        }
        return buffer.lines.isEmpty ? "(no output)" : buffer.lines.joined(separator: "\n")
    }

    private static func evaluateLua(_ code: String) -> String {
        guard let context = JSContext(),
              let bundleURL = Bundle.main.url(forResource: "fengari-web", withExtension: "js"),
              let bundle = try? String(contentsOf: bundleURL, encoding: .utf8) else {
            return "Error: the Lua runtime is missing from the app."
        }
        let buffer = LogBuffer()
        context.exceptionHandler = { _, exception in
            buffer.error = exception?.toString()
        }
        context.evaluateScript("var window = this;")
        context.evaluateScript(bundle)
        context.setObject(code, forKeyedSubscript: "__source" as NSString)
        let result = context.evaluateScript(luaRunner)?.toString() ?? ""
        if let error = buffer.error {
            return "Error: \(error)"
        }
        return result.isEmpty ? "(no output)" : result
    }

    /// Runs the Lua source in a fresh Lua state, with `print` writing to the result.
    private static let luaRunner = """
    (function (source) {
      var F = window.fengari;
      var out = [];
      var L = F.lauxlib.luaL_newstate();
      F.lualib.luaL_openlibs(L);
      F.lua.lua_pushjsfunction(L, function (L2) {
        var count = F.lua.lua_gettop(L2);
        var parts = [];
        for (var i = 1; i <= count; i++) {
          var kind = F.lua.lua_type(L2, i);
          if (kind === F.lua.LUA_TSTRING || kind === F.lua.LUA_TNUMBER) parts.push(String(F.lua.lua_tojsstring(L2, i)));
          else if (kind === F.lua.LUA_TBOOLEAN) parts.push(F.lua.lua_toboolean(L2, i) ? "true" : "false");
          else if (kind === F.lua.LUA_TNIL) parts.push("nil");
          else parts.push("(value)");
        }
        out.push(parts.join("\\t"));
        return 0;
      });
      F.lua.lua_setglobal(L, F.to_luastring("print"));
      var status = F.lauxlib.luaL_loadstring(L, F.to_luastring(source));
      if (status === F.lua.LUA_OK) status = F.lua.lua_pcall(L, 0, 0, 0);
      if (status !== F.lua.LUA_OK) out.push("Error: " + F.lua.lua_tojsstring(L, -1));
      return out.length ? out.join("\\n") : "(no output)";
    })(__source)
    """
}
