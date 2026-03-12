// ============================================================
//  ArchiveCloud Dashboard — script.js
//  Simulates shell script output in the terminal
//  Matches real output format of upload.sh / archive.sh / monitor.sh
// ============================================================

const terminal = document.getElementById('output');
let selectedFile = null;

// ── Terminal helpers ─────────────────────────────────────────
function clearTerminal() {
  terminal.innerHTML = '<span class="prompt">archivecloud@aws</span><span class="cursor"> $ </span>terminal cleared.';
}

function log(text, type = '') {
  const span = document.createElement('span');
  span.className = type ? `log-${type}` : '';
  span.textContent = '\n' + text;
  terminal.appendChild(span);
  terminal.scrollTop = terminal.scrollHeight;
}

function logCmd(cmd) {
  const line = document.createElement('span');
  line.innerHTML = '\n<span class="prompt">archivecloud@aws</span><span class="cursor"> $ </span>' + cmd;
  terminal.appendChild(line);
  terminal.scrollTop = terminal.scrollHeight;
}

function logLines(lines, delayMs = 80) {
  lines.forEach(([text, type], i) => {
    setTimeout(() => {
      log(text, type);
      terminal.scrollTop = terminal.scrollHeight;
    }, i * delayMs);
  });
  return lines.length * delayMs;
}

// ── File select ──────────────────────────────────────────────
function onFileSelect(input) {
  const file = input.files[0];
  if (!file) return;
  selectedFile = file;
  const label = document.getElementById('fileLabel');
  label.textContent = file.name + '  (' + formatBytes(file.size) + ')';
  document.getElementById('fileDrop').classList.add('has-file');
}

function formatBytes(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / 1048576).toFixed(1) + ' MB';
}

// Archive radio toggle
document.querySelectorAll('input[name="archiveMode"]').forEach(radio => {
  radio.addEventListener('change', () => {
    const keyInput = document.getElementById('archiveKey');
    keyInput.style.display = radio.value === 'single' ? 'block' : 'none';
  });
});

// ── Upload ───────────────────────────────────────────────────
function uploadFile() {
  if (!selectedFile) {
    logCmd('./upload.sh');
    log('  [XX]  No file specified. Usage: ./upload.sh <file>', 'err');
    return;
  }

  const fname = selectedFile.name;
  const bucket = 'archivecloud-1773311716';
  const ts = new Date().toISOString().replace(/[-:.]/g, '').slice(0, 15) + 'Z';
  const size = formatBytes(selectedFile.size);

  logCmd('./upload.sh ' + fname);
  log('');
  log('  ArchiveCloud - Upload', 'section');
  log('  =====================');

  const steps = [
    ['  [..]  Uploading ' + fname + ' → s3://' + bucket + '/uploads/' + fname, 'info'],
    ['  [OK]  Uploaded: s3://' + bucket + '/uploads/' + fname, 'ok'],
    ['', ''],
    ['  [..]  Verifying upload...', 'info'],
    ['--------------------------------------', ''],
    ['|  ContentLength  |  ' + size.padEnd(10) + '          |', ''],
    ['|  Encryption     |  AES256               |', ''],
    ['|  Modified       |  ' + new Date().toUTCString().slice(0, 22) + '  |', ''],
    ['--------------------------------------', ''],
    ['  [OK]  File confirmed in S3', 'ok'],
    ['', ''],
    ['  [..]  Writing audit entry to SSM...', 'info'],
    ['  [OK]  SSM audit: /archivecloud/uploads/' + ts + '_' + fname, 'ok'],
    ['', ''],
    ['  [OK]  Done. s3://' + bucket + '/uploads/' + fname + ' is live.', 'ok'],
  ];

  logLines(steps, 90);

  // Update status bar after
  setTimeout(() => {
    setStatVal('s3', 'ACTIVE', 'ok');
    setStatVal('ssm', 'ACTIVE', 'ok');
    setInfraVal('inf-s3', '1 object', 'running');
  }, steps.length * 90 + 200);
}

// ── Archive ──────────────────────────────────────────────────
function archiveFiles() {
  const mode = document.querySelector('input[name="archiveMode"]:checked').value;
  const key = mode === 'single' ? document.getElementById('archiveKey').value.trim() : '';
  const cmd = key ? './archive.sh ' + key : './archive.sh';
  const bucket = 'archivecloud-1773311716';
  const ts = new Date().toISOString().replace(/[-:.]/g, '').slice(0, 15) + 'Z';

  logCmd(cmd);
  log('');
  log('  ArchiveCloud - Archive to Glacier', 'section');
  log('  ===================================');

  const steps = [
    ['  [..]  Scanning s3://' + bucket + '/uploads/ for STANDARD objects...', 'info'],
    ['', ''],
    ['  [..]  Archiving: uploads/report.pdf', 'info'],
    ['  [OK]  Archived → GLACIER: uploads/report.pdf', 'ok'],
    ['  [..]  Archiving: uploads/data.csv', 'info'],
    ['  [OK]  Archived → GLACIER: uploads/data.csv', 'ok'],
    ['', ''],
    ['  [..]  Verifying Glacier storage class...', 'info'],
    ['------------------------------------------------', ''],
    ['|  Key                   |  Class    |', ''],
    ['|  uploads/report.pdf    |  GLACIER  |', ''],
    ['|  uploads/data.csv      |  GLACIER  |', ''],
    ['------------------------------------------------', ''],
    ['', ''],
    ['  [OK]  SSM audit: /archivecloud/archive/' + ts, 'ok'],
    ['', ''],
    ['  [OK]  2 file(s) moved to Glacier.', 'ok'],
  ];

  logLines(steps, 100);

  setTimeout(() => {
    setStatVal('glacier', 'ACTIVE', 'ok');
    setStatVal('ssm', 'ACTIVE', 'ok');
    setInfraVal('inf-glacier', '2 files', 'ok');
  }, steps.length * 100 + 200);
}

// ── Monitor ──────────────────────────────────────────────────
function monitorSystem() {
  const service = document.getElementById('monitorService').value;
  logCmd('./monitor.sh ' + service);
  log('');
  log('  ArchiveCloud - Monitor', 'section');
  log('  ========================');

  if (service === 'all') {
    runMonitorAll();
  } else {
    runMonitorSingle(service);
  }
}

function runMonitorAll() {
  const bucket = 'archivecloud-1773311716';
  const account = '238240855081';

  const steps = [
    ['', ''],
    ['  === IAM ===', 'section'],
    ['  [OK]  Account  : ' + account, 'ok'],
    ['  [OK]  Identity : arn:aws:sts::' + account + ':assumed-role/voclabs/user', 'ok'],
    ['', ''],
    ['  === EC2 ===', 'section'],
    ['  -------------------------------------------------------', ''],
    ['  | ID           | State   | IP           | Type       |', ''],
    ['  | i-09ea25983  | running | 54.x.x.x     | t2.micro   |', ''],
    ['  -------------------------------------------------------', ''],
    ['  [OK]  EC2 query complete', 'ok'],
    ['', ''],
    ['  === S3 ===', 'section'],
    ['  [..]  Bucket: ' + bucket, 'info'],
    ['  | TotalObjects |  6  |', ''],
    ['  [OK]  S3 query complete', 'ok'],
    ['', ''],
    ['  === S3 Glacier ===', 'section'],
    ['  [..]  Objects by storage class', 'info'],
    ['    STANDARD             4 objects', ''],
    ['    STANDARD_IA          0 objects', ''],
    ['    GLACIER              2 objects', ''],
    ['  [OK]  Glacier query complete', 'ok'],
    ['', ''],
    ['  === EKS ===', 'section'],
    ['  | Name             | Status | Version |', ''],
    ['  | archivecloud-eks | ACTIVE | 1.29    |', ''],
    ['  | archivecloud-nodes | ACTIVE | t3.small | 1 |', ''],
    ['  [OK]  EKS query complete', 'ok'],
    ['', ''],
    ['  === AWS Glue ===', 'section'],
    ['  | Name                 | State | LastUpdated |', ''],
    ['  | archivecloud-crawler | READY | ' + new Date().toLocaleDateString() + '  |', ''],
    ['  [OK]  Glue query complete', 'ok'],
    ['', ''],
    ['  === CloudWatch ===', 'section'],
    ['  | Metric          | Dimension              |', ''],
    ['  | FilesUploaded   | ' + bucket + ' |', ''],
    ['  | GlacierArchives | ' + bucket + ' |', ''],
    ['  | EKSNodesActive  | archivecloud-eks       |', ''],
    ['  | archivecloud-no-uploads        | INSUFFICIENT_DATA |', ''],
    ['  | archivecloud-glacier-activity  | INSUFFICIENT_DATA |', ''],
    ['  [OK]  CloudWatch query complete', 'ok'],
    ['', ''],
    ['  === SNS ===', 'section'],
    ['  | arn:aws:sns:us-east-1:' + account + ':archivecloud-alerts |', ''],
    ['  [OK]  SNS query complete', 'ok'],
    ['', ''],
    ['  === Systems Manager ===', 'section'],
    ['  | i-09ea25983  | Online | Amazon Linux 2023 |', ''],
    ['  | /archivecloud/uploads/...  | String |', ''],
    ['  | /archivecloud/archive/...  | String |', ''],
    ['  [OK]  SSM query complete', 'ok'],
    ['', ''],
    ['  [OK]  All services checked.', 'ok'],
  ];

  const total = logLines(steps, 60);

  setTimeout(() => {
    setStatVal('iam',        'ACTIVE', 'ok');
    setStatVal('ec2',        'RUNNING', 'ok');
    setStatVal('s3',         'ACTIVE', 'ok');
    setStatVal('glacier',    'ACTIVE', 'ok');
    setStatVal('eks',        'ACTIVE', 'ok');
    setStatVal('glue',       'READY', 'ok');
    setStatVal('cw',         'ACTIVE', 'ok');
    setStatVal('sns',        'ACTIVE', 'ok');
    setStatVal('ssm',        'ONLINE', 'ok');
    setInfraVal('inf-ec2',     'running',  'running');
    setInfraVal('inf-eks',     'ACTIVE',   'ok');
    setInfraVal('inf-s3',      '6 objects','running');
    setInfraVal('inf-glacier', '2 files',  'ok');
    setInfraVal('inf-cw',      '2 alarms', 'warn');
    setInfraVal('inf-sns',     'active',   'ok');
  }, total + 300);
}

function runMonitorSingle(service) {
  const serviceOutputs = {
    iam:        [['  [OK]  Account  : 238240855081', 'ok'], ['  [OK]  Identity : arn:aws:sts::238240855081:assumed-role/voclabs/user', 'ok']],
    ec2:        [['  | i-09ea25983 | running | 54.x.x.x | t2.micro |', ''], ['  [OK]  EC2 query complete', 'ok']],
    s3:         [['  [..]  Bucket: archivecloud-1773311716', 'info'], ['  | TotalObjects | 6 |', ''], ['  [OK]  S3 query complete', 'ok']],
    glacier:    [['    STANDARD     4 objects', ''], ['    GLACIER      2 objects', ''], ['  [OK]  Glacier query complete', 'ok']],
    eks:        [['  | archivecloud-eks | ACTIVE | 1.29 |', ''], ['  | archivecloud-nodes | ACTIVE | t3.small | 1 |', ''], ['  [OK]  EKS query complete', 'ok']],
    glue:       [['  | archivecloud-crawler | READY |', ''], ['  [OK]  Glue query complete', 'ok']],
    cloudwatch: [['  | FilesUploaded  | archivecloud-1773311716 |', ''], ['  | archivecloud-no-uploads | INSUFFICIENT_DATA |', ''], ['  [OK]  CloudWatch query complete', 'ok']],
    sns:        [['  | arn:aws:sns:us-east-1:238240855081:archivecloud-alerts |', ''], ['  [OK]  SNS query complete', 'ok']],
    ssm:        [['  | i-09ea25983 | Online | Amazon Linux 2023 |', ''], ['  [OK]  SSM query complete', 'ok']],
  };

  const output = serviceOutputs[service] || [['  [!!]  Unknown service: ' + service, 'warn']];
  log('');
  log('  === ' + service.toUpperCase() + ' ===', 'section');
  logLines(output, 100);

  setTimeout(() => {
    setStatVal(service === 'cloudwatch' ? 'cw' : service, 'ACTIVE', 'ok');
  }, output.length * 100 + 200);
}

// ── Refresh status ────────────────────────────────────────────
function refreshStatus() {
  logCmd('aws ec2/eks/s3/cloudwatch describe ...');
  log('  [..]  Refreshing infrastructure status...', 'info');

  setTimeout(() => {
    setInfraVal('inf-ec2',     'running',   'running');
    setInfraVal('inf-eks',     'ACTIVE',    'ok');
    setInfraVal('inf-s3',      '6 objects', 'running');
    setInfraVal('inf-glacier', '2 files',   'ok');
    setInfraVal('inf-cw',      '2 alarms',  'warn');
    setInfraVal('inf-sns',     'active',    'ok');
    log('  [OK]  Infrastructure status refreshed.', 'ok');
  }, 800);
}

// ── DOM helpers ───────────────────────────────────────────────
function setStatVal(id, text, cls) {
  const el = document.getElementById('val-' + id);
  if (!el) return;
  el.textContent = text;
  el.className = 'stat-value ' + cls;
}

function setInfraVal(id, text, cls) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = text;
  el.className = 'infra-val ' + cls;
}