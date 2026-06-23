import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p; // ignore: depend_on_referenced_packages

import '../models/conversation.dart';
import '../models/conversation_mode.dart';
import '../models/llm_config.dart';
import '../models/media_attachment.dart';
import '../models/message.dart';
import '../models/session.dart';

/// 对话持久化服务 — 基于 sqflite
class ConversationService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'tessera.db');

    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            config TEXT NOT NULL,
            system_prompt TEXT,
            mode TEXT NOT NULL DEFAULT 'normal',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
            parent_session_id TEXT REFERENCES sessions(id),
            type TEXT NOT NULL DEFAULT 'main',
            title TEXT,
            mode TEXT NOT NULL DEFAULT 'normal',
            status TEXT NOT NULL DEFAULT 'active',
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_sessions_conv ON sessions(conversation_id)',
        );

        await db.execute('''
          CREATE TABLE messages (
            id TEXT NOT NULL,
            conv_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL DEFAULT '',
            thinking TEXT,
            media_attachments TEXT,
            tool_calls TEXT,
            tool_call_id TEXT,
            status TEXT NOT NULL DEFAULT 'completed',
            error_message TEXT,
            timestamp TEXT NOT NULL,
            session_id TEXT REFERENCES sessions(id),
            metadata TEXT,
            FOREIGN KEY (conv_id) REFERENCES conversations(id) ON DELETE CASCADE,
            PRIMARY KEY (id, conv_id)
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_messages_conv ON messages(conv_id, timestamp)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE messages ADD COLUMN thinking TEXT');
          await db.execute(
            'ALTER TABLE messages ADD COLUMN media_attachments TEXT',
          );
        }
        if (oldVersion < 3) {
          // 1. conversations 表增加 mode 列
          await db.execute(
            "ALTER TABLE conversations ADD COLUMN mode TEXT NOT NULL DEFAULT 'normal'",
          );

          // 2. 新建 sessions 表
          await db.execute('''
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
              parent_session_id TEXT REFERENCES sessions(id),
              type TEXT NOT NULL DEFAULT 'main',
              title TEXT,
              mode TEXT NOT NULL DEFAULT 'normal',
              status TEXT NOT NULL DEFAULT 'active',
              sort_order INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_sessions_conv ON sessions(conversation_id)',
          );

          // 3. messages 表增加 session_id 和 metadata 列
          await db.execute(
            'ALTER TABLE messages ADD COLUMN session_id TEXT REFERENCES sessions(id)',
          );
          await db.execute(
            'ALTER TABLE messages ADD COLUMN metadata TEXT',
          );

          // 4. 为每个已有对话创建主 Session 记录
          await db.execute('''
            INSERT INTO sessions (id, conversation_id, type, mode, status, sort_order, created_at, updated_at)
            SELECT id, id, 'main', mode, 'active', 0, created_at, updated_at FROM conversations
          ''');

          // 5. 将已有消息的 session_id 设为其对话 ID
          await db.execute(
            'UPDATE messages SET session_id = conv_id WHERE session_id IS NULL',
          );
        }
      },
    );
  }

  /// 保存对话（插入或更新）
  Future<void> saveConversation(Conversation conv) async {
    final db = await database;
    final msgCount = conv.messages.length;
    await db.transaction((txn) async {
      await txn.insert('conversations', {
        'id': conv.id,
        'title': conv.title,
        'config': jsonEncode(conv.config.toJson()),
        'system_prompt': conv.systemPrompt,
        'mode': conv.mode.name,
        'created_at': conv.createdAt.toIso8601String(),
        'updated_at': conv.updatedAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 删除旧消息后重新插入
      await txn.delete('messages', where: 'conv_id = ?', whereArgs: [conv.id]);

      for (final msg in conv.messages) {
        await txn.insert('messages', {
          'id': msg.id,
          'conv_id': conv.id,
          'role': msg.role.name,
          'content': msg.content,
          'thinking': msg.thinking,
          'media_attachments': msg.mediaAttachments != null
              ? jsonEncode(
                  msg.mediaAttachments!.map((a) => a.toJson()).toList(),
                )
              : null,
          'tool_calls': msg.toolCalls != null
              ? jsonEncode(msg.toolCalls!.map((t) => t.toJson()).toList())
              : null,
          'tool_call_id': msg.toolCallId,
          'status': msg.status.name,
          'error_message': msg.errorMessage,
          'timestamp': msg.timestamp.toIso8601String(),
          'session_id': msg.sessionId,
          'metadata': msg.metadata != null ? jsonEncode(msg.metadata) : null,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    debugPrint(
      '[ConversationService] 保存对话: id=${conv.id}, title=${conv.title}, mode=${conv.mode.name}, messages=$msgCount',
    );
  }

  /// 获取所有对话列表（不含消息）
  Future<List<Conversation>> listConversations() async {
    final db = await database;
    final rows = await db.query('conversations', orderBy: 'updated_at DESC');

    return rows
        .map(
          (row) => Conversation(
            id: row['id'] as String,
            title: row['title'] as String,
            config: LlmConfig.fromJson(jsonDecode(row['config'] as String)),
            systemPrompt: row['system_prompt'] as String?,
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
            mode: row['mode'] != null
                ? ConversationMode.fromName(row['mode'] as String)
                : ConversationMode.normal,
          ),
        )
        .toList();
  }

  /// 获取单个对话（含消息）
  Future<Conversation?> getConversation(String id) async {
    final db = await database;

    final convRows = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (convRows.isEmpty) return null;

    // 加载该对话的所有 Session
    final sessionRows = await db.query(
      'sessions',
      where: 'conversation_id = ?',
      whereArgs: [id],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    final sessions = sessionRows
        .map((row) => Session(
              id: row['id'] as String,
              conversationId: row['conversation_id'] as String,
              parentSessionId: row['parent_session_id'] as String?,
              type: SessionType.fromName(row['type'] as String? ?? 'main'),
              title: row['title'] as String? ?? '',
              mode: ConversationMode.fromName(row['mode'] as String? ?? 'normal'),
              status: SessionStatus.fromName(row['status'] as String? ?? 'active'),
              sortOrder: row['sort_order'] as int? ?? 0,
              createdAt: DateTime.parse(row['created_at'] as String),
              updatedAt: DateTime.parse(row['updated_at'] as String),
            ))
        .toList();

    final msgRows = await db.query(
      'messages',
      where: 'conv_id = ?',
      whereArgs: [id],
      orderBy: 'timestamp ASC',
    );

    final messages = msgRows
        .map(
          (row) => Message(
            id: row['id'] as String,
            role: MessageRole.values.firstWhere((r) => r.name == row['role']),
            content: row['content'] as String,
            thinking: row['thinking'] as String?,
            mediaAttachments: row['media_attachments'] != null
                ? (jsonDecode(row['media_attachments'] as String) as List)
                      .map(
                        (e) =>
                            MediaAttachment.fromJson(e as Map<String, dynamic>),
                      )
                      .toList()
                : null,
            toolCalls: row['tool_calls'] != null
                ? (jsonDecode(row['tool_calls'] as String) as List)
                      .map((e) => ToolCall.fromJson(e as Map<String, dynamic>))
                      .toList()
                : null,
            toolCallId: row['tool_call_id'] as String?,
            status: MessageStatus.values.firstWhere(
              (s) => s.name == row['status'],
            ),
            errorMessage: row['error_message'] as String?,
            timestamp: DateTime.parse(row['timestamp'] as String),
            sessionId: row['session_id'] as String?,
            metadata: row['metadata'] != null
                ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
                : null,
          ),
        )
        .toList();

    final row = convRows.first;
    return Conversation(
      id: row['id'] as String,
      title: row['title'] as String,
      messages: messages,
      config: LlmConfig.fromJson(jsonDecode(row['config'] as String)),
      systemPrompt: row['system_prompt'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      mode: row['mode'] != null
          ? ConversationMode.fromName(row['mode'] as String)
          : ConversationMode.normal,
      activeSessionId: id, // 默认激活主 Session
      sessions: sessions,
    );
  }

  /// 重命名对话
  Future<void> renameConversation(String id, String newTitle) async {
    final db = await database;
    await db.update(
      'conversations',
      {'title': newTitle, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删除对话
  Future<void> deleteConversation(String id) async {
    final db = await database;
    await db.delete('conversations', where: 'id = ?', whereArgs: [id]);
  }

  /// 获取对话数量
  Future<int> getConversationCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM conversations',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  // ── Session CRUD ──

  /// 创建 Session
  Future<String> createSession(Session session) async {
    final db = await database;
    await db.insert('sessions', {
      'id': session.id,
      'conversation_id': session.conversationId,
      'parent_session_id': session.parentSessionId,
      'type': session.type.name,
      'title': session.title,
      'mode': session.mode.name,
      'status': session.status.name,
      'sort_order': session.sortOrder,
      'created_at': session.createdAt.toIso8601String(),
      'updated_at': session.updatedAt.toIso8601String(),
    });
    debugPrint(
      '[ConversationService] 创建 Session: id=${session.id}, type=${session.type.name}, title=${session.title}',
    );
    return session.id;
  }

  /// 获取对话的所有 Session
  Future<List<Session>> getSessions(String conversationId) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows
        .map((row) => Session(
              id: row['id'] as String,
              conversationId: row['conversation_id'] as String,
              parentSessionId: row['parent_session_id'] as String?,
              type: SessionType.fromName(row['type'] as String? ?? 'main'),
              title: row['title'] as String? ?? '',
              mode: ConversationMode.fromName(row['mode'] as String? ?? 'normal'),
              status: SessionStatus.fromName(row['status'] as String? ?? 'active'),
              sortOrder: row['sort_order'] as int? ?? 0,
              createdAt: DateTime.parse(row['created_at'] as String),
              updatedAt: DateTime.parse(row['updated_at'] as String),
            ))
        .toList();
  }

  /// 获取单个 Session
  Future<Session?> getSession(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return Session(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String,
      parentSessionId: row['parent_session_id'] as String?,
      type: SessionType.fromName(row['type'] as String? ?? 'main'),
      title: row['title'] as String? ?? '',
      mode: ConversationMode.fromName(row['mode'] as String? ?? 'normal'),
      status: SessionStatus.fromName(row['status'] as String? ?? 'active'),
      sortOrder: row['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  /// 更新 Session 状态
  Future<void> updateSessionStatus(String sessionId, SessionStatus status) async {
    final db = await database;
    await db.update(
      'sessions',
      {
        'status': status.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 更新 Session 标题
  Future<void> updateSessionTitle(String sessionId, String title) async {
    final db = await database;
    await db.update(
      'sessions',
      {
        'title': title,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 删除 Session
  Future<void> deleteSession(String sessionId) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  /// 按 Session 查询消息
  Future<List<Message>> getMessagesBySession(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
    return rows
        .map(
          (row) => Message(
            id: row['id'] as String,
            role: MessageRole.values.firstWhere((r) => r.name == row['role']),
            content: row['content'] as String,
            thinking: row['thinking'] as String?,
            mediaAttachments: row['media_attachments'] != null
                ? (jsonDecode(row['media_attachments'] as String) as List)
                      .map(
                        (e) =>
                            MediaAttachment.fromJson(e as Map<String, dynamic>),
                      )
                      .toList()
                : null,
            toolCalls: row['tool_calls'] != null
                ? (jsonDecode(row['tool_calls'] as String) as List)
                      .map((e) => ToolCall.fromJson(e as Map<String, dynamic>))
                      .toList()
                : null,
            toolCallId: row['tool_call_id'] as String?,
            status: MessageStatus.values.firstWhere(
              (s) => s.name == row['status'],
            ),
            errorMessage: row['error_message'] as String?,
            timestamp: DateTime.parse(row['timestamp'] as String),
            sessionId: row['session_id'] as String?,
            metadata: row['metadata'] != null
                ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
                : null,
          ),
        )
        .toList();
  }

  /// 保存单条消息（供子 Agent 使用）
  Future<void> saveMessage(Message msg, String conversationId, String sessionId) async {
    final db = await database;
    await db.insert('messages', {
      'id': msg.id,
      'conv_id': conversationId,
      'role': msg.role.name,
      'content': msg.content,
      'thinking': msg.thinking,
      'media_attachments': msg.mediaAttachments != null
          ? jsonEncode(msg.mediaAttachments!.map((a) => a.toJson()).toList())
          : null,
      'tool_calls': msg.toolCalls != null
          ? jsonEncode(msg.toolCalls!.map((t) => t.toJson()).toList())
          : null,
      'tool_call_id': msg.toolCallId,
      'status': msg.status.name,
      'error_message': msg.errorMessage,
      'timestamp': msg.timestamp.toIso8601String(),
      'session_id': sessionId,
      'metadata': msg.metadata != null ? jsonEncode(msg.metadata) : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
