const output = document.getElementById("output");

function log(text){
    output.textContent += "\n" + text;
    output.scrollTop = output.scrollHeight;
}

function uploadFile(){
    const file = document.getElementById("fileInput").files[0];
    if(!file){
        alert("Select a file first");
        return;
    }
    log("Uploading file: " + file.name);
    log("Running: ./upload.sh " + file.name);
    log("Checking IAM credentials...");
    log("Uploading to S3 bucket...");
    log("Upload complete");
}

function archiveFiles(){
    log("Starting archive process...");
    log("Running: ./archive.sh glacier-move");
    log("Scanning S3 bucket...");
    log("Moving objects to Glacier...");
    log("Archive completed ");
}

function monitorSystem(){
    log("Running system monitoring...");
    log("Running: ./monitor.sh all");
    setTimeout(()=>{
        log("Lightsail instance: RUNNING");
        log("EKS cluster: ACTIVE");
        log("SSM agents: ONLINE");
        log("X-Ray traces: OK");
    },1000);
}

function simulateStatus(){
    document.getElementById("ls").textContent = "Running";
    document.getElementById("eks").textContent = "Active";
    document.getElementById("s3").textContent = "Available";
    log("Infrastructure status refreshed.");
}