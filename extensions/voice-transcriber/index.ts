/**
 * Voice Transcriber Plugin for OpenClaw
 * Automatically transcribes voice messages using local whisper.cpp
 *
 * Requirements:
 *   - whisper.cpp built with CUDA (or CPU)
 *   - ffmpeg (for OGG -> WAV conversion)
 *   - ~/.openclaw/scripts/transcribe.sh
 *
 * See docs/VOICE-TRANSCRIPTION.md for setup instructions.
 */

import type { PluginApi } from "openclaw";
import * as fs from "fs";
import * as path from "path";
import * as https from "https";
import * as http from "http";
import { execSync } from "child_process";

// ---------------------------------------------------------------------------
// Error handling
// ---------------------------------------------------------------------------

interface TranscriptionError {
  category: string;
  detail: string;
  userMessage: string;
}

const ERROR_MESSAGES: Record<string, string> = {
  FFMPEG_MISSING: "Cannot process audio: ffmpeg is not installed.",
  WHISPER_MISSING: "Cannot transcribe: whisper-cli not found.",
  MODEL_MISSING: "Cannot transcribe: whisper model not found.",
  CUDA_ERROR: "GPU (CUDA) error during transcription. Server restart may be needed.",
  GPU_OOM: "Not enough GPU memory. Try a shorter voice message.",
  FFMPEG_FAILED: "Failed to convert audio file. It may be corrupted.",
  WHISPER_FAILED: "Transcription error.",
  EMPTY_RESULT: "Transcription returned empty. Audio may be silent or corrupted.",
  DISK_FULL: "Not enough disk space to process audio.",
  FILE_NOT_FOUND: "Audio file not found.",
  USAGE: "Transcription script usage error.",
  TIMEOUT: "Transcription timed out (2 min limit). Try a shorter message.",
  DOWNLOAD_FAILED: "Failed to download voice message from Telegram.",
  UNKNOWN: "Unknown transcription error.",
};

const OPENCLAW_HOME = process.env.OPENCLAW_HOME || path.join(process.env.HOME || "", ".openclaw");
const TRANSCRIBE_SCRIPT = path.join(OPENCLAW_HOME, "scripts", "transcribe.sh");

function parseOutput(output: string): { text: string } | TranscriptionError {
  const trimmed = output.trim();
  if (trimmed.startsWith("ERROR:")) {
    const parts = trimmed.split(":");
    const category = parts[1] || "UNKNOWN";
    const detail = parts.slice(2).join(":").trim();
    return { category, detail, userMessage: ERROR_MESSAGES[category] || ERROR_MESSAGES.UNKNOWN };
  }
  return { text: trimmed };
}

function isError(r: any): r is TranscriptionError {
  return r != null && "category" in r && "userMessage" in r;
}

// ---------------------------------------------------------------------------
// Transcription
// ---------------------------------------------------------------------------

function transcribe(audioPath: string, language: string): { text: string } | TranscriptionError {
  try {
    const result = execSync(`${TRANSCRIBE_SCRIPT} "${audioPath}" "${language}"`, {
      encoding: "utf-8",
      timeout: 120_000,
      maxBuffer: 10 * 1024 * 1024,
    });
    const parsed = parseOutput(result);
    if (isError(parsed)) return parsed;
    if (!parsed.text) {
      return { category: "EMPTY_RESULT", detail: "Empty stdout", userMessage: ERROR_MESSAGES.EMPTY_RESULT };
    }
    return parsed;
  } catch (error: any) {
    if (error.killed) {
      return { category: "TIMEOUT", detail: "Killed after timeout", userMessage: ERROR_MESSAGES.TIMEOUT };
    }
    const out = (error.stdout || error.stderr || error.message || "").toString();
    const parsed = parseOutput(out);
    if (isError(parsed)) return parsed;
    return { category: "UNKNOWN", detail: error.message || "", userMessage: ERROR_MESSAGES.UNKNOWN };
  }
}

// ---------------------------------------------------------------------------
// Telegram helpers
// ---------------------------------------------------------------------------

function sendTelegram(chatId: string | number, threadId: string | number | undefined, text: string, replyTo?: number): void {
  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  if (!botToken) return;
  const body: Record<string, any> = { chat_id: chatId, text };
  if (threadId) body.message_thread_id = Number(threadId);
  if (replyTo) body.reply_to_message_id = replyTo;
  const data = JSON.stringify(body);
  const req = https.request(
    `https://api.telegram.org/bot${botToken}/sendMessage`,
    { method: "POST", headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) } },
    (res) => { res.resume(); },
  );
  req.on("error", (e) => console.error(`[voice-transcriber] Telegram send error: ${e.message}`));
  req.write(data);
  req.end();
}

function downloadFile(url: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("https") ? https : http;
    client.get(url, (res) => {
      if ((res.statusCode === 301 || res.statusCode === 302) && res.headers.location) {
        downloadFile(res.headers.location).then(resolve).catch(reject);
        return;
      }
      const chunks: Buffer[] = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve(Buffer.concat(chunks)));
      res.on("error", reject);
    }).on("error", reject);
  });
}

function getFileUrl(fileId: string): Promise<string | null> {
  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  if (!botToken) return Promise.resolve(null);
  return new Promise((resolve) => {
    https.get(`https://api.telegram.org/bot${botToken}/getFile?file_id=${fileId}`, (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => {
        try {
          const json = JSON.parse(data);
          resolve(json.ok && json.result?.file_path ? `https://api.telegram.org/file/bot${botToken}/${json.result.file_path}` : null);
        } catch { resolve(null); }
      });
    }).on("error", () => resolve(null));
  });
}

// ---------------------------------------------------------------------------
// Plugin entry
// ---------------------------------------------------------------------------

export default function (api: PluginApi) {
  const config = api.config?.plugins?.entries?.["voice-transcriber"]?.config || {};
  const voiceTopicId = (config.voiceTopicId || process.env.VOICE_TOPIC_ID || "7").toString();
  const transcriptsPath = config.transcriptsPath || "topics/voice/transcripts";
  const language = config.language || "en";

  console.log(`[voice-transcriber] Plugin loaded (topic: ${voiceTopicId}, lang: ${language})`);

  if (!fs.existsSync(TRANSCRIBE_SCRIPT)) {
    console.error(`[voice-transcriber] Script not found: ${TRANSCRIBE_SCRIPT}`);
    console.warn("[voice-transcriber] Transcription disabled — see docs/VOICE-TRANSCRIPTION.md");
    return;
  }

  // Manual transcription tool
  api.registerTool({
    name: "transcribe_audio",
    description: "Transcribe audio/voice file to text using local GPU-accelerated whisper.cpp",
    parameters: {
      type: "object",
      properties: {
        audioUrl: { type: "string", description: "URL to audio file" },
        audioPath: { type: "string", description: "Local path to audio file" },
        language: { type: "string", description: "Language code (en, ru, de, etc.)", default: "en" },
      },
    },
    handler: async ({ audioUrl, audioPath, language: lang }) => {
      let filePath = audioPath;
      let temp = false;
      if (!filePath || !fs.existsSync(filePath)) {
        if (audioUrl) {
          const buf = await downloadFile(audioUrl);
          filePath = `/tmp/voice_${Date.now()}.ogg`;
          fs.writeFileSync(filePath, buf);
          temp = true;
        } else {
          return { error: "No audio source provided" };
        }
      }
      const result = transcribe(filePath, lang || language);
      if (temp && filePath) try { fs.unlinkSync(filePath); } catch {}
      if (isError(result)) return { error: result.userMessage, errorCategory: result.category };
      return { transcription: result.text };
    },
  });

  // Automatic voice message handling
  api.on("message_received", async (msg: any) => {
    const voice = msg.voice || msg.audio;
    if (!voice) return;

    const meta = msg.metadata || {};
    const topicId = (meta.threadId ?? meta.message_thread_id ?? "").toString();
    const toField = (meta.to || "").replace(/^telegram:/, "");
    const chatId = toField || meta.chatId || msg.chat?.id;
    const messageId = meta.message_id || msg.message_id;

    console.log(`[voice-transcriber] Voice in topic ${topicId}`);

    let tempFile: string | null = null;
    try {
      const fileUrl = await getFileUrl(voice.file_id);
      if (!fileUrl) {
        sendTelegram(chatId, topicId, `\u26a0\ufe0f ${ERROR_MESSAGES.DOWNLOAD_FAILED}`, messageId);
        msg.content = `[Transcription error]: ${ERROR_MESSAGES.DOWNLOAD_FAILED}`;
        return;
      }

      const buf = await downloadFile(fileUrl);
      tempFile = `/tmp/voice_${Date.now()}.ogg`;
      fs.writeFileSync(tempFile, buf);

      const result = transcribe(tempFile, language);

      if (isError(result)) {
        console.error(`[voice-transcriber] ${result.category}: ${result.detail}`);
        sendTelegram(chatId, topicId, `\u26a0\ufe0f ${result.userMessage}`, messageId);
        msg.content = `[Transcription error]: ${result.userMessage}`;
        return;
      }

      console.log(`[voice-transcriber] OK: ${result.text.substring(0, 80)}...`);

      // Save transcript in Voice topic
      if (topicId === voiceTopicId) {
        const workspace = api.config?.agents?.defaults?.workspace || path.join(OPENCLAW_HOME, "workspace");
        const dir = path.join(workspace, transcriptsPath);
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        const date = new Date();
        const file = path.join(dir, `${date.toISOString().split("T")[0]}.md`);
        const time = date.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
        fs.appendFileSync(file, `\n## ${time}\n\n${result.text}\n`);
        console.log(`[voice-transcriber] Saved to ${file}`);
      }

      msg.transcription = result.text;
      msg.content = `[Voice transcription]:\n${result.text}`;
    } catch (error: any) {
      console.error(`[voice-transcriber] Unexpected: ${error.message}`);
      sendTelegram(chatId, topicId, `\u26a0\ufe0f ${ERROR_MESSAGES.UNKNOWN}`, messageId);
      msg.content = `[Transcription error]: ${ERROR_MESSAGES.UNKNOWN}`;
    } finally {
      if (tempFile && fs.existsSync(tempFile)) try { fs.unlinkSync(tempFile); } catch {}
    }
  });

  console.log("[voice-transcriber] Hooks registered");
}
