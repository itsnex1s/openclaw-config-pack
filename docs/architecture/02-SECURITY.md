# Security Architecture

## Threat Matrix

| Threat | Attack Vector | Defense |
|--------|--------------|---------|
| Unauthorized Access | DM from unknown user | Telegram allowlist (2 IDs) |
| Direct Prompt Injection | "Ignore instructions" | Regex filter (5 rules) + CIF (22 patterns) + 3-strike |
| Indirect Prompt Injection | Instructions in files/URLs | CIF trust levels + prompt-guard quarantine |
| System Prompt Extraction | "Reveal your prompt" | CIF refusals (no oracle leak) + SOUL.md CRITICAL |
| Command Execution | Shell injection via tools | sandbox mode + tools.deny: exec |
| Data Exfiltration | Web requests from sandbox | network: none + deny: web_fetch, browser |
| DDoS | Mass requests | Cloudflare WAF + rate limiting |
| Port Scanning | Open port discovery | bind: loopback + UFW firewall |
| Credential Theft | Access to API keys | chmod 600 + log redaction + GPG backups |
| Malicious Skill | Trojan in SKILL.md | skill-guard audit + manual review |
| Privilege Escalation | systemd/process abuse | NoNewPrivileges + ProtectKernel* + MemoryMax |

## Telegram Authorization Flow

```
User sends message
      │
      ▼
Telegram Servers ──webhook──> Cloudflare Tunnel ──localhost──> Gateway
                                                                  │
                                                           Check allowFrom
                                                            │         │
                                                           YES        NO
                                                            │         │
                                                         PROCESS   DROP (silent)
```

## Security Flow (Mermaid)

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant T as Telegram
    participant CF as Cloudflare
    participant G as Gateway
    participant S as Security Filter
    participant CIF as CIF (SECURITY.md)
    participant A as Agent
    participant OR as OpenRouter

    U->>T: Send message
    T->>CF: Bot API webhook
    CF->>G: Tunnel (localhost)
    G->>S: Check allowFrom

    alt User NOT in allowlist
        S-->>G: REJECT
        Note over G: Silent drop
    else User in allowlist
        S-->>G: PASS
        G->>S: Check input patterns (regex)

        alt Regex injection match
            S-->>G: REJECT
            G-->>T: "Request blocked"
        else Regex clean
            S-->>G: PASS
            G->>CIF: Trust level check + injection patterns
            Note over CIF: SECURITY.md: 22 patterns<br/>prompt-guard: canary, encoding<br/>Graduated response (strikes)

            alt CIF: injection detected
                CIF-->>G: Generic refusal (no oracle leak)
                G-->>T: "I can't help with that."
            else CIF: clean
                CIF-->>G: PASS
                G->>A: Process message
                Note over A: SOUL.md CRITICAL rules active
                A->>OR: LLM request
                OR-->>A: Response
                A->>S: Filter output (redact secrets)
                S-->>A: Sanitized
                A-->>G: Reply
                G-->>T: Send message
                T-->>U: Response
            end
        end
    end
```

## Threat Model (Mermaid)

```mermaid
flowchart LR
    subgraph Threats["THREATS"]
        T1["Unauthorized Access"]
        T2["Direct Prompt Injection"]
        T3["Indirect Prompt Injection"]
        T4["System Prompt Extraction"]
        T5["Data Exfiltration"]
        T6["Command Execution"]
        T7["DDoS Attack"]
        T8["Malicious Skill"]
        T9["Privilege Escalation"]
    end

    subgraph Defenses["DEFENSES"]
        D1["Telegram allowlist"]
        D2["Regex input filter"]
        D3["CIF (SECURITY.md)"]
        D4["prompt-guard skill"]
        D5["SOUL.md CRITICAL rules"]
        D6["network: none"]
        D7["tools deny: exec"]
        D8["Cloudflare WAF"]
        D9["skill-guard audit"]
        D10["systemd hardening"]
    end

    T1 -->|blocked by| D1
    T2 -->|blocked by| D2
    T2 -->|blocked by| D3
    T3 -->|blocked by| D4
    T4 -->|blocked by| D5
    T5 -->|blocked by| D6
    T6 -->|blocked by| D7
    T7 -->|blocked by| D8
    T8 -->|blocked by| D9
    T9 -->|blocked by| D10
```
