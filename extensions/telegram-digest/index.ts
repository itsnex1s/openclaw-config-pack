import type { PluginApi } from "openclaw";
import { execSync } from "child_process";
import { existsSync, readFileSync } from "fs";
import { join } from "path";
import * as https from "https";

const OPENCLAW_HOME = process.env.OPENCLAW_HOME || join(process.env.HOME || "", ".openclaw");
const SCRIPT_PATH = join(OPENCLAW_HOME, "scripts", "telegram-digest.py");
const CHANNELS_CONFIG = join(OPENCLAW_HOME, "scripts", "digest-channels.json");
const VENV_PYTHON = join(OPENCLAW_HOME, "scripts", "digest-venv", "bin", "python3");
const ENV_FILE = join(OPENCLAW_HOME, "credentials", ".env");

const DIGEST_TOPIC_ID = process.env.DIGEST_TOPIC_ID || "121";

function loadEnv(): Record<string, string> {
  const envVars: Record<string, string> = { ...process.env } as any;
  if (existsSync(ENV_FILE)) {
    const content = readFileSync(ENV_FILE, "utf-8");
    for (const line of content.split("\n")) {
      const trimmed = line.trim();
      if (trimmed && !trimmed.startsWith("#")) {
        const eqIdx = trimmed.indexOf("=");
        if (eqIdx > 0) {
          envVars[trimmed.slice(0, eqIdx)] = trimmed.slice(eqIdx + 1);
        }
      }
    }
  }
  return envVars;
}

function sendTelegramMessage(chatId: string | number, threadId: string | number, text: string, replyTo?: number): void {
  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  if (!botToken) return;

  const body: Record<string, any> = {
    chat_id: chatId,
    text,
    message_thread_id: Number(threadId),
    parse_mode: "HTML",
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
  req.on("error", (err) => console.error(`[telegram-digest] Telegram send error: ${err.message}`));
  req.write(postData);
  req.end();
}

export default function (api: PluginApi) {
  console.log("[telegram-digest] Plugin loaded");

  api.on("message_received", async (msg: any) => {
    const meta = msg.metadata || {};
    const topicId = (meta.threadId ?? meta.message_thread_id ?? "").toString();
    if (topicId !== DIGEST_TOPIC_ID) return;

    const text = (msg.content || "").trim().toLowerCase();
    if (!text) return;

    const toField = (meta.to || "").replace(/^telegram:/, "");
    const chatId = toField || meta.chatId;
    const messageId = meta.message_id;

    // Command: trigger digest
    if (/^(digest|run|trigger)$/i.test(text)) {
      console.log("[telegram-digest] Manual digest triggered");
      sendTelegramMessage(chatId, topicId, "Starting digest collection...", messageId);

      if (!existsSync(SCRIPT_PATH)) {
        sendTelegramMessage(chatId, topicId, `Script not found: ${SCRIPT_PATH}`, messageId);
        msg.content = "[telegram-digest] Handled: script not found";
        return;
      }

      const python = existsSync(VENV_PYTHON) ? VENV_PYTHON : "python3";
      try {
        const output = execSync(`${python} "${SCRIPT_PATH}"`, {
          encoding: "utf-8",
          timeout: 120_000,
          env: loadEnv(),
          cwd: join(OPENCLAW_HOME, "scripts"),
          stdio: ["pipe", "pipe", "pipe"],
        }).trim();
        sendTelegramMessage(chatId, topicId, output || "Digest complete.", messageId);
      } catch (err: any) {
        sendTelegramMessage(chatId, topicId, `Error: ${err.message}`, messageId);
      }
      msg.content = "[telegram-digest] Handled: trigger";
      return;
    }

    // Command: list channels
    if (/^(channels?|list)$/i.test(text)) {
      if (!existsSync(CHANNELS_CONFIG)) {
        sendTelegramMessage(chatId, topicId, `Channel config not found: ${CHANNELS_CONFIG}`, messageId);
        msg.content = "[telegram-digest] Handled: no config";
        return;
      }

      try {
        const config = JSON.parse(readFileSync(CHANNELS_CONFIG, "utf-8"));
        const channels = config.channels || [];
        const lines = channels.map((ch: string, i: number) => `${i + 1}. ${ch}`);
        const info = [
          `Tracked channels (${channels.length}):`,
          ...lines,
          "",
          `Max messages/channel: ${config.maxMessagesPerChannel || 200}`,
          `Period: ${config.lookbackHours || 24}h`,
        ].join("\n");
        sendTelegramMessage(chatId, topicId, info, messageId);
      } catch (err: any) {
        sendTelegramMessage(chatId, topicId, `Error reading config: ${err.message}`, messageId);
      }
      msg.content = "[telegram-digest] Handled: channels";
      return;
    }

    // Other messages — let the agent handle
  });

  console.log("[telegram-digest] Event hooks registered");
}
