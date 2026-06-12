-- ============================================================================
-- 示例插件：Hello Plugin
-- 演示 tessera 桥接 API：register_tool / register_skill / log
-- 同时演示 addons: http.get + json.decode + base64.encode
-- ============================================================================

tessera.log("Hello Plugin 正在加载...")

-- ---------------------------------------------------------------------------
-- 注册一个 SKILL（技能描述注入 System Prompt）
-- ---------------------------------------------------------------------------
tessera.register_skill({
  name = "问候技能",
  description = "我有一个 greeting 工具，可以用不同语言向用户打招呼；"
    .. "还有一个 fetch_ip 工具，可以查询当前出口 IP。"
})

-- ---------------------------------------------------------------------------
-- 注册一个 TOOL（LLM 可调用的工具）
-- ---------------------------------------------------------------------------
tessera.register_tool({
  name = "greeting",
  description = "用指定语言向用户打招呼",
  parameters = {
    name = {
      type = "string",
      description = "要问候的用户名",
      required = true
    },
    language = {
      type = "string",
      description = "使用的语言（如 zh, en, ja, fr）",
      required = false
    }
  },
  handler = function(args)
    local name = args["name"] or "World"
    local lang = args["language"] or "zh"

    tessera.log("greeting called: name=" .. name .. ", lang=" .. lang)

    local greetings = {
      zh = "你好，" .. name .. "！欢迎使用 Tessera 插件系统。",
      en = "Hello, " .. name .. "! Welcome to Tessera plugin system.",
      ja = "こんにちは、" .. name .. "さん！Tessera プラグインシステムへようこそ。",
      fr = "Bonjour, " .. name .. "! Bienvenue dans le système de plugins Tessera.",
      de = "Hallo, " .. name .. "! Willkommen im Tessera Plugin-System.",
      es = "¡Hola, " .. name .. "! Bienvenido al sistema de plugins de Tessera.",
    }

    if greetings[lang] then
      return greetings[lang]
    end
    return "Hello, " .. name .. "! (unsupported language: " .. lang .. ")"
  end
})

-- ---------------------------------------------------------------------------
-- 演示 addons: 调用 http.get + json.decode 解析外部 API
-- ---------------------------------------------------------------------------
tessera.register_tool({
  name = "fetch_ip",
  description = "查询当前出口 IP 地址 (演示 http + json addon)",
  parameters = {},
  handler = function(_)
    -- 简单 GET,10 秒超时
    local resp, err = http.get(
      "https://api.ipify.org?format=json",
      { timeout = 10 }
    )
    if not resp then
      return "网络错误: " .. err
    end
    if not resp.ok then
      return "HTTP " .. resp.status .. ": " .. resp.body
    end
    local data = json.decode(resp.body)
    if not data then
      return "无法解析响应: " .. resp.body
    end
    return "你的 IP 是: " .. (data["ip"] or "未知")
  end
})

-- ---------------------------------------------------------------------------
-- 演示 addons: base64 编解码 + http.request 通用入口
-- ---------------------------------------------------------------------------
tessera.register_tool({
  name = "echo_token",
  description = "演示 base64 编码,把传入的 token 编码后返回 (无网络)",
  parameters = {
    text = {
      type = "string",
      description = "要编码的明文",
      required = true
    }
  },
  handler = function(args)
    local text = args["text"] or ""
    local encoded = base64.encode(text)
    -- 验证 round-trip
    local decoded = base64.decode(encoded)
    if decoded ~= text then
      return "round-trip 失败"
    end
    return "base64(" .. text .. ") = " .. encoded
  end
})

tessera.log("Hello Plugin 加载完成")
