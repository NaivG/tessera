import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p; // ignore: depend_on_referenced_packages

import '../models/conversation.dart';
import '../models/llm_config.dart';
import '../models/media_attachment.dart';
import '../models/message.dart';

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
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            config TEXT NOT NULL,
            system_prompt TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

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
      },
    );
  }

  /// 保存对话（插入或更新）
  Future<void> saveConversation(Conversation conv) async {
    final db = await database;
    final msgCount = conv.messages.length;
    await db.transaction((txn) async {
      await txn.insert(
        'conversations',
        {
          'id': conv.id,
          'title': conv.title,
          'config': jsonEncode(conv.config.toJson()),
          'system_prompt': conv.systemPrompt,
          'created_at': conv.createdAt.toIso8601String(),
          'updated_at': conv.updatedAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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
        });
      }
    });
    debugPrint('[ConversationService] 保存对话: id=${conv.id}, title=${conv.title}, messages=$msgCount');
  }

  /// 获取所有对话列表（不含消息）
  Future<List<Conversation>> listConversations() async {
    final db = await database;
    final rows = await db.query('conversations', orderBy: 'updated_at DESC');

    return rows.map((row) => Conversation(
      id: row['id'] as String,
      title: row['title'] as String,
      config: LlmConfig.fromJson(jsonDecode(row['config'] as String)),
      systemPrompt: row['system_prompt'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    )).toList();
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

    final msgRows = await db.query(
      'messages',
      where: 'conv_id = ?',
      whereArgs: [id],
      orderBy: 'timestamp ASC',
    );

    final messages = msgRows.map((row) => Message(
      id: row['id'] as String,
      role: MessageRole.values.firstWhere((r) => r.name == row['role']),
      content: row['content'] as String,
      thinking: row['thinking'] as String?,
      mediaAttachments: row['media_attachments'] != null
          ? (jsonDecode(row['media_attachments'] as String) as List)
              .map((e) =>
                  MediaAttachment.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      toolCalls: row['tool_calls'] != null
          ? (jsonDecode(row['tool_calls'] as String) as List)
              .map((e) => ToolCall.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      toolCallId: row['tool_call_id'] as String?,
      status: MessageStatus.values.firstWhere((s) => s.name == row['status']),
      errorMessage: row['error_message'] as String?,
      timestamp: DateTime.parse(row['timestamp'] as String),
    )).toList();

    final row = convRows.first;
    return Conversation(
      id: row['id'] as String,
      title: row['title'] as String,
      messages: messages,
      config: LlmConfig.fromJson(jsonDecode(row['config'] as String)),
      systemPrompt: row['system_prompt'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
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
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM conversations');
    return (result.first['count'] as int?) ?? 0;
  }
}
