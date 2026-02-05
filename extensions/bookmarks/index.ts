import type { PluginApi } from "openclaw";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { join, dirname } from "path";
import * as https from "https";

const OPENCLAW_HOME = process.env.OPENCLAW_HOME || join(process.env.HOME || "", ".openclaw");
const BOOKMARKS_FILE = join(OPENCLAW_HOME, "workspace", "topics", "bookmarks", "BOOKMARKS.json");
const BOOKMARKS_TOPIC_ID = process.env.BOOKMARKS_TOPIC_ID || "125";

interface Bookmark {
  id: number;
  url: string;
  title: string;
  addedAt: string;
  read: boolean;
}

function loadBookmarks(): Bookmark[] {
  if (!existsSync(BOOKMARKS_FILE)) return [];
  try {
    return JSON.parse(readFileSync(BOOKMARKS_FILE, "utf-8"));
  } catch {
    return [];
  }
}

function saveBookmarks(bookmarks: Bookmark[]): void {
  const dir = dirname(BOOKMARKS_FILE);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(BOOKMARKS_FILE, JSON.stringify(bookmarks, null, 2), "utf-8");
}

function nextId(bookmarks: Bookmark[]): number {
  return bookmarks.length === 0 ? 1 : Math.max(...bookmarks.map((b) => b.id)) + 1;
}

function formatList(bookmarks: Bookmark[], filter?: "unread"): string {
  let items = bookmarks;
  if (filter === "unread") items = items.filter((b) => !b.read);
  if (items.length === 0) return filter === "unread" ? "No unread bookmarks." : "No bookmarks yet.";
  return items
    .map((b) => `#${b.id} ${b.read ? "✓" : "•"} ${b.title || b.url}\n   ${b.url} (${b.addedAt})`)
    .join("\n\n");
}

function sendTelegramMessage(chatId: string | number, threadId: string | number, text: string, replyTo?: number): void {
  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  if (!botToken) return;

  const body: Record<string, any> = {
    chat_id: chatId,
    text,
    message_thread_id: Number(threadId),
    parse_mode: "HTML",
    disable_web_page_preview: true,
  };
  if (replyTo) body.reply_to_message_id = replyTo;

  const postData = JSON.stringify(body);
  const req = https.request(
    `https://api.telegram.org/bot${botToken}/sendMessage`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(postData) },
    },
    (res) => { res.resume(); }
  );
  req.on("error", (err) => console.error(`[bookmarks] Telegram send error: ${err.message}`));
  req.write(postData);
  req.end();
}

export default function (api: PluginApi) {
  console.log("[bookmarks] Plugin loaded");

  api.on("message_received", async (msg: any) => {
    const meta = msg.metadata || {};
    const topicId = (meta.threadId ?? meta.message_thread_id ?? "").toString();
    if (topicId !== BOOKMARKS_TOPIC_ID) return;

    const text = (msg.content || "").trim();
    if (!text) return;

    const toField = (meta.to || "").replace(/^telegram:/, "");
    const chatId = toField || meta.chatId;
    const messageId = meta.message_id;

    console.log(`[bookmarks] Matched topic ${topicId}, text="${text.slice(0, 80)}"`);

    // Command: list bookmarks
    if (/^(list|bookmarks?|all)$/i.test(text)) {
      const result = formatList(loadBookmarks());
      sendTelegramMessage(chatId, topicId, result, messageId);
      msg.content = "[bookmarks] Handled: list";
      return;
    }

    // Command: unread bookmarks
    if (/^(unread)$/i.test(text)) {
      const result = formatList(loadBookmarks(), "unread");
      sendTelegramMessage(chatId, topicId, result, messageId);
      msg.content = "[bookmarks] Handled: unread";
      return;
    }

    // Command: mark as read
    const readMatch = text.match(/^(?:read)\s*#?(\d+)$/i);
    if (readMatch) {
      const id = parseInt(readMatch[1], 10);
      const bookmarks = loadBookmarks();
      const bm = bookmarks.find((b) => b.id === id);
      if (bm) {
        bm.read = true;
        saveBookmarks(bookmarks);
        sendTelegramMessage(chatId, topicId, `Bookmark #${id} marked as read.`, messageId);
      } else {
        sendTelegramMessage(chatId, topicId, `Bookmark #${id} not found.`, messageId);
      }
      msg.content = "[bookmarks] Handled: mark read";
      return;
    }

    // URL detected — save bookmark
    const urlMatch = text.match(/https?:\/\/[^\s<>"{}|\\^`\[\]]+/i);
    if (urlMatch) {
      const url = urlMatch[0];
      const bookmarks = loadBookmarks();
      const existing = bookmarks.find((b) => b.url === url);
      if (existing) {
        sendTelegramMessage(chatId, topicId, `Already saved as #${existing.id}.`, messageId);
      } else {
        const title = text.replace(url, "").trim() || url;
        const bm: Bookmark = {
          id: nextId(bookmarks),
          url,
          title,
          addedAt: new Date().toISOString().slice(0, 10),
          read: false,
        };
        bookmarks.push(bm);
        saveBookmarks(bookmarks);
        sendTelegramMessage(chatId, topicId, `Saved bookmark #${bm.id}: ${url}`, messageId);
        console.log(`[bookmarks] Saved: ${url}`);
      }
      msg.content = `[bookmarks] Handled: save ${url}`;
      return;
    }

    // No URL and no command — let the agent handle it
  });

  console.log("[bookmarks] Event hooks registered");
}
