# ArchiveCloud — AWS Cloud Archive & Monitoring System
---

## Project Overview

ArchiveCloud is a web-based cloud archive and real-time monitoring system built on 8 AWS services, designed as part of an HCI academic project. It demonstrates how humans interact with cloud infrastructure through a visual dashboard, automated scripts, and secure communication channels.

---

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │        User (Browser / CLI)          │
                    └───────────────┬─────────────────────┘
                                    │
         ┌──────────────────────────▼───────────────────────────┐
         │              Application Layer                        │
         │  ┌─────────────┐  ┌────────────┐  ┌──────────────┐    │
         │  │ Upload files│  │  Monitor   │  │  Archive     │    │
         │  │  (upload.sh)│  │(monitor.sh)│  │(archive.sh)  │    │
         │  └──────┬──────┘  └─────┬──────┘  └──────┬───────┘    │
         └─────────┼───────────────┼─────────────────┼──────────┘
              ┌─────────────────────▼──────────────────────┐
              │                    IAM                      │
              │   Authenticates every API call              │
              └─────────────────────┬──────────────────────┘
                                    │
                                    |
    ┌──────────────▼───┐  ┌────────▼────────┐  ┌────▼────────────┐
    │  Amazon EKS      │  │      EC2        │  │ Amazon S3       │
    │archive containers│  │  (hosting)      │  │ (uploads)       │
    └──────────────────┘  └─────────────────┘  └─────────────────┘
                   │               │                 │
    ┌──────────────▼───┐  ┌────────▼────────┐  ┌────▼────────────┐
    │   System Manager │  │  CloudWatch     │  │ AWS Glue        │
    │ store and audit  │  │  (tracing)      │  │ (data catalog)  │
    └──────────────────┘  └─────────────────┘  └─────────────────┘
                   │               │                 │

                                    │
                    ┌───────────────▼──────────────┐
                    │         Amazon SNS           │
                    │ (Email alerts + secure comms)│
                    └──────────────────────────────┘
```

---

## AWS Services — Roles & Justification

## Project Structure

```
aws-archive-project/
├── UserInterface/
│   └── index.html          ← Full web app (upload + monitor + archive tabs)
├── Scripts/
│   ├── upload.sh           <- Upload files to S3 via AWS CLI (Linux/macOS)
│   ├── archive.sh          <- move and archive
│   └── monitor.sh          <- monitor
├── Powershell/
│   └── upload.ps1          <- Upload script for Windows users
└── Documents/
    ├── architecture.jpg    <- Architecture diagram image
    └── services.md <- This file
```

### Prerequisites
- AWS account with $50 credit applied
- AWS CLI v2 installed and configured (`aws configure`)
- Bash (Linux/macOS) or PowerShell 5+ (Windows)


*Built for HCI Academic Project — AWS us-east-1 — Budget: $50*