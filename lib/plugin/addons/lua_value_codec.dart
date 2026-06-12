// =============================================================================
// LuaValueCodec — Dart ↔ Lua 双向值转换
//
// 供 LuaPluginHost 的 tessera 桥接 与 addons (json/http/…) 共用,
// 保证插件中无论参数传递还是 JSON 编解码都使用同一套类型语义。
//
// 设计要点:
//   - push 时:Dart List → 整型键 1..n 的 table; Dart Map → 字符串键 table
//   - read 时:默认所有 table 读为 Map<String, dynamic> (向后兼容 host 桥接)
//   - read(detectArray: true) 时:
//        若 table 的键集恰好是 {1..n} 的连续正整数 → List<dynamic>
//        否则 → Map<String, dynamic>
//        空 table → Map<String, dynamic>{} (符合 JSON 对象语义)
// =============================================================================

import 'package:luax/lua.dart';

class LuaValueCodec {
  LuaValueCodec._();

  // ---------------------------------------------------------------------------
  // Dart → Lua
  // ---------------------------------------------------------------------------

  /// 递归地将 Dart 值压入栈顶。
  ///
  /// 支持的映射:
  ///   null      → nil
  ///   bool      → boolean
  ///   int       → integer
  ///   double    → number
  ///   String    → string
  ///   List      → table (整型键 1..n)
  ///   Map       → table (键被 toString)
  ///   其他对象  → string (toString)
  static void pushDart(LuaState ls, dynamic value) {
    if (value == null) {
      ls.pushNil();
    } else if (value is bool) {
      ls.pushBoolean(value);
    } else if (value is int) {
      ls.pushInteger(value);
    } else if (value is double) {
      ls.pushNumber(value);
    } else if (value is String) {
      ls.pushString(value);
    } else if (value is List) {
      ls.newTable();
      for (int i = 0; i < value.length; i++) {
        ls.pushInteger(i + 1);
        pushDart(ls, value[i]);
        ls.setTable(-3);
      }
    } else if (value is Map) {
      ls.newTable();
      value.forEach((k, v) {
        ls.pushString(k.toString());
        pushDart(ls, v);
        ls.setTable(-3);
      });
    } else {
      ls.pushString(value.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Lua → Dart
  // ---------------------------------------------------------------------------

  /// 读取栈位 [idx] 处的 Lua 值并转为 Dart。
  ///
  /// [detectArray] 控制 table 的解读:
  ///   - false (默认):始终返回 `Map<String, dynamic>`,与 host 桥接一致
  ///   - true:键集是 {1..n} 连续正整数 → `List<dynamic>`,否则 `Map<String, dynamic>`
  static dynamic readLua(LuaState ls, int idx, {bool detectArray = false}) {
    final t = ls.type(idx);
    switch (t) {
      case LuaType.luaNil:
        return null;
      case LuaType.luaBoolean:
        return ls.toBoolean(idx);
      case LuaType.luaNumber:
        if (ls.isInteger(idx)) return ls.toInteger(idx);
        return ls.toNumber(idx);
      case LuaType.luaString:
        return ls.toStr(idx) ?? '';
      case LuaType.luaTable:
        // pushValue 让 table 位于栈顶,方便 next 迭代
        ls.pushValue(idx);
        final result = detectArray ? _readTableAuto(ls) : _readTableAsMap(ls);
        ls.pop(1);
        return result;
      default:
        return ls.toStr(idx);
    }
  }

  // ---------------------------------------------------------------------------
  // 内部:table 读取
  // ---------------------------------------------------------------------------

  /// 假设 table 已在栈顶。读取为 `Map<String, dynamic>`。
  static Map<String, dynamic> _readTableAsMap(LuaState ls) {
    final result = <String, dynamic>{};
    ls.pushNil();
    while (ls.next(-2)) {
      // key 在 -2,value 在 -1
      final key = _luaKeyToString(ls, -2);
      if (key != null) {
        result[key] = readLua(ls, -1);
      }
      ls.pop(1); // 弹 value 保留 key 供下次 next
    }
    return result;
  }

  /// 假设 table 已在栈顶。
  /// 若键集恰好是 {1..n} → 返回 List;否则返回 Map。空 table → 空 Map。
  static dynamic _readTableAuto(LuaState ls) {
    final keys = <dynamic>[];
    final values = <dynamic>[];

    ls.pushNil();
    while (ls.next(-2)) {
      dynamic k;
      if (ls.isInteger(-2)) {
        k = ls.toInteger(-2);
      } else if (ls.isNumber(-2)) {
        k = ls.toNumber(-2);
      } else if (ls.type(-2) == LuaType.luaString) {
        k = ls.toStr(-2);
      }
      if (k != null) {
        keys.add(k);
        values.add(readLua(ls, -1, detectArray: true));
      }
      ls.pop(1);
    }

    if (keys.isEmpty) return <String, dynamic>{};

    // 数组判定:所有键都是 int 且集合 == {1..n}
    final allInt = keys.every((k) => k is int);
    if (allInt) {
      final intKeySet = keys.cast<int>().toSet();
      final isArray = intKeySet.length == keys.length &&
          List.generate(keys.length, (i) => i + 1)
              .every(intKeySet.contains);
      if (isArray) {
        final arr = List<dynamic>.filled(keys.length, null);
        for (int idx = 0; idx < keys.length; idx++) {
          arr[(keys[idx] as int) - 1] = values[idx];
        }
        return arr;
      }
    }

    // 当作字典
    final map = <String, dynamic>{};
    for (int idx = 0; idx < keys.length; idx++) {
      map[keys[idx].toString()] = values[idx];
    }
    return map;
  }

  /// 从栈位 [idx] 读取 key,转为字符串(用于 Map 键)。
  /// 非 string/number 键返回 null,调用方应跳过该 entry。
  static String? _luaKeyToString(LuaState ls, int idx) {
    if (ls.type(idx) == LuaType.luaString) {
      return ls.toStr(idx);
    } else if (ls.isInteger(idx)) {
      return ls.toInteger(idx).toString();
    } else if (ls.isNumber(idx)) {
      return ls.toNumber(idx).toString();
    }
    return null;
  }
}
