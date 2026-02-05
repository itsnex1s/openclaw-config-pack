import type { PluginApi } from "openclaw";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { join, dirname } from "path";
import * as https from "https";

const OPENCLAW_HOME = process.env.OPENCLAW_HOME || join(process.env.HOME || "", ".openclaw");
const WORKSPACE = join(OPENCLAW_HOME, "workspace");
const TODO_FILE = join(WORKSPACE, "topics", "tasks", "TODO.md");
const DONE_FILE = join(WORKSPACE, "topics", "tasks", "DONE.md");

const TASKS_TOPIC_ID = process.env.TASKS_TOPIC_ID || "11";

function ensureFile(filePath: string): void {
  if (!existsSync(filePath)) {
    mkdirSync(dirname(filePath), { recursive: true });
    writeFileSync(filePath, "", "utf-8");
  }
}

function readFile(filePath: string): string {
  ensureFile(filePath);
  return readFileSync(filePath, "utf-8");
}

function todayStr(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function sendTelegramMessage(
  chatId: string | number,
  threadId: string | number,
  text: string,
  replyTo?: number
): void {
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
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(postData),
      },
    },
    (res) => {
      res.resume();
    }
  );
  req.on("error", (err) =>
    console.error(`[task-manager] Telegram send error: ${err.message}`)
  );
  req.write(postData);
  req.end();
}

/**
 * Parse task lines from TODO.md.
 * Expected format:
 *   - [ ] #N [YYYY-MM-DD] [P2] description @due(YYYY-MM-DD)
 *     - [ ] #N.1 subtask
 */
interface Task {
  raw: string;
  id: string;
  date: string;
  priority: string;
  description: string;
  due: string | null;
  subtasks: { raw: string; id: string; description: string }[];
}

function parseTasks(content: string): Task[] {
  const lines = content.split("\n");
  const tasks: Task[] = [];
  let current: Task | null = null;

  for (const line of lines) {
    // Top-level task: - [ ] #N [date] [priority] description
    const taskMatch = line.match(
      /^- \[ \] #(\S+)\s+\[(\d{4}-\d{2}-\d{2})\]\s+\[([^\]]+)\]\s+(.+)$/
    );
    if (taskMatch) {
      const dueMatch = taskMatch[4].match(/@due\((\d{4}-\d{2}-\d{2})\)/);
      current = {
        raw: line,
        id: taskMatch[1],
        date: taskMatch[2],
        priority: taskMatch[3],
        description: taskMatch[4],
        due: dueMatch ? dueMatch[1] : null,
        subtasks: [],
      };
      tasks.push(current);
      continue;
    }

    // Subtask:   - [ ] #N.1 description
    const subMatch = line.match(/^\s+- \[ \] #(\S+)\s+(.+)$/);
    if (subMatch && current) {
      current.subtasks.push({
        raw: line,
        id: subMatch[1],
        description: subMatch[2],
      });
    }
  }

  return tasks;
}

function handleDone(
  taskId: string,
  chatId: string | number,
  threadId: string,
  messageId?: number
): void {
  const today = todayStr();
  const todoContent = readFile(TODO_FILE);
  const lines = todoContent.split("\n");
  let found = false;
  let movedLine = "";
  const remaining: string[] = [];
  const isSubtask = taskId.includes(".");

  for (const line of lines) {
    // Match the exact task/subtask ID
    const idPattern = new RegExp(
      `^(\\s*)- \\[ \\] #${taskId.replace(".", "\\.")}\\b`
    );
    if (idPattern.test(line)) {
      found = true;
      movedLine = line
        .replace(/^(\s*)- \[ \]/, "$1- [x]")
        .replace(/$/, ` (completed ${today})`);
    } else {
      remaining.push(line);
    }
  }

  if (!found) {
    sendTelegramMessage(
      chatId,
      threadId,
      `Task #${taskId} not found in TODO.md.`,
      messageId
    );
    return;
  }

  // Write updated TODO.md
  writeFileSync(TODO_FILE, remaining.join("\n"), "utf-8");

  // Append to DONE.md under today's header
  ensureFile(DONE_FILE);
  let doneContent = readFileSync(DONE_FILE, "utf-8");
  const header = `## ${today}`;

  if (!doneContent.includes(header)) {
    doneContent = doneContent.trimEnd() + `\n\n${header}\n`;
  }

  // Insert the completed task under the header
  const headerIdx = doneContent.indexOf(header);
  const insertPos = headerIdx + header.length + 1;
  doneContent =
    doneContent.slice(0, insertPos) +
    movedLine +
    "\n" +
    doneContent.slice(insertPos);

  writeFileSync(DONE_FILE, doneContent, "utf-8");

  const label = isSubtask ? "Subtask" : "Task";
  sendTelegramMessage(
    chatId,
    threadId,
    `✅ ${label} #${taskId} completed.`,
    messageId
  );
}

function handleStatus(
  chatId: string | number,
  threadId: string,
  messageId?: number
): void {
  const tasks = parseTasks(readFile(TODO_FILE));
  if (tasks.length === 0) {
    sendTelegramMessage(chatId, threadId, "No open tasks. ✨", messageId);
    return;
  }

  let msg = `<b>Open tasks (${tasks.length})</b>\n\n`;
  for (const t of tasks) {
    const dueStr = t.due ? ` @due(${t.due})` : "";
    msg += `• #${t.id} [${t.priority}] ${escapeHtml(t.description.replace(/@due\([^)]+\)/, "").trim())}${dueStr}\n`;
    for (const s of t.subtasks) {
      msg += `  ◦ #${s.id} ${escapeHtml(s.description)}\n`;
    }
  }

  sendTelegramMessage(chatId, threadId, msg.trim(), messageId);
}

function handleOverdue(
  chatId: string | number,
  threadId: string,
  messageId?: number
): void {
  const today = todayStr();
  const tasks = parseTasks(readFile(TODO_FILE));
  const overdue = tasks.filter((t) => t.due !== null && t.due < today);

  if (overdue.length === 0) {
    sendTelegramMessage(
      chatId,
      threadId,
      "No overdue tasks. 👍",
      messageId
    );
    return;
  }

  let msg = `<b>⏰ Overdue tasks (${overdue.length})</b>\n\n`;
  for (const t of overdue) {
    msg += `• #${t.id} [${t.priority}] ${escapeHtml(t.description.replace(/@due\([^)]+\)/, "").trim())} — due ${t.due}\n`;
  }

  sendTelegramMessage(chatId, threadId, msg.trim(), messageId);
}

function handlePriority(
  taskId: string,
  newPriority: string,
  chatId: string | number,
  threadId: string,
  messageId?: number
): void {
  const todoContent = readFile(TODO_FILE);
  const lines = todoContent.split("\n");
  let found = false;
  const updated: string[] = [];

  const idPattern = new RegExp(
    `^(- \\[ \\] #${taskId.replace(".", "\\.")}\\s+\\[\\d{4}-\\d{2}-\\d{2}\\]\\s+\\[)[^\\]]+(\\].*)$`
  );

  for (const line of lines) {
    const m = line.match(idPattern);
    if (m) {
      found = true;
      updated.push(m[1] + newPriority + m[2]);
    } else {
      updated.push(line);
    }
  }

  if (!found) {
    sendTelegramMessage(
      chatId,
      threadId,
      `Task #${taskId} not found in TODO.md.`,
      messageId
    );
    return;
  }

  writeFileSync(TODO_FILE, updated.join("\n"), "utf-8");
  sendTelegramMessage(
    chatId,
    threadId,
    `Priority of #${taskId} set to [${newPriority}].`,
    messageId
  );
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

export default function (api: PluginApi) {
  console.log("[task-manager] Plugin loaded");

  api.on("message_received", async (msg: any) => {
    const meta = msg.metadata || {};
    const topicId = (
      meta.threadId ??
      meta.message_thread_id ??
      ""
    ).toString();
    if (topicId !== TASKS_TOPIC_ID) return;

    const text = (msg.content || "").trim();
    if (!text) return;

    const toField = (meta.to || "").replace(/^telegram:/, "");
    const chatId = toField || meta.chatId;
    const messageId = meta.message_id;

    console.log(
      `[task-manager] Matched topic ${topicId}, text="${text.slice(0, 80)}", chatId=${chatId}`
    );

    // Command: done #N / done #N.1
    const doneMatch = text.match(
      /^(?:done|готово|выполнено)\s+#?(\d+(?:\.\d+)?)\s*$/i
    );
    if (doneMatch) {
      handleDone(doneMatch[1], chatId, topicId, messageId);
      msg.content = `[task-manager] Handled: done #${doneMatch[1]}`;
      return;
    }

    // Command: status / today
    if (/^(?:status|today|статус|сегодня|задачи)$/i.test(text)) {
      handleStatus(chatId, topicId, messageId);
      msg.content = "[task-manager] Handled: status";
      return;
    }

    // Command: overdue
    if (/^(?:overdue|просрочен|просроченные)$/i.test(text)) {
      handleOverdue(chatId, topicId, messageId);
      msg.content = "[task-manager] Handled: overdue";
      return;
    }

    // Command: priority #N P1/P2/P3
    const prioMatch = text.match(
      /^(?:priority|приоритет)\s+#?(\d+(?:\.\d+)?)\s+(P[123]|высокий|средний|низкий|high|medium|low)$/i
    );
    if (prioMatch) {
      const prioMap: Record<string, string> = {
        p1: "P1",
        p2: "P2",
        p3: "P3",
        высокий: "P1",
        средний: "P2",
        низкий: "P3",
        high: "P1",
        medium: "P2",
        low: "P3",
      };
      const normalized =
        prioMap[prioMatch[2].toLowerCase()] || prioMatch[2].toUpperCase();
      handlePriority(prioMatch[1], normalized, chatId, topicId, messageId);
      msg.content = `[task-manager] Handled: priority #${prioMatch[1]} ${normalized}`;
      return;
    }

    // Fall-through: any other text is NOT handled by the plugin
    // — let the LLM agent handle new tasks, complex requests, questions
  });

  console.log("[task-manager] Event hooks registered");
}
