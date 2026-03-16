#!/bin/bash


LOG_FILE="${LOG_FILE:-aou_mtdna_analysis_launcher.log}"
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

#### PARAMETERS
# step 1: set parameters (todo update for large scale analysis)
log "Defining parameters."
export numTest=1
export numIter=1
export JOBLIMIT=10
export outputFold=mtDNA_v25_pilot_5
export PORTID=8094
export USE_MEM=32
export SQL_DB_NAME="local_cromwell_run.db" # name of local SQL database
export FORCEDOWNLOAD='False' # if enabled, will force download for CRAM via gsutil -u {} cp
export RERUN_FAIL='False' # if enabled, will try to rerun failures. If disabled, will filter out failures.
export FILE_DONE="mt_pipeline_single_2_5_stats.tsv" # expects this to be in the current bucket
export FILE_FAIL="mt_pipeline_single_2_5_failures.tsv" # samples that have failed along with log files

#### CLEAN UP PRIOR RUN ARTIFACTS
log "Cleaning prior run artifacts."
rm -f mtDNA_v25_pilot_5_prog_*.failure.tsv \
  mtDNA_v25_pilot_5_prog_*.running.tsv \
  mtDNA_v25_pilot_5_prog_*.sample_mapping.tsv \
  mtDNA_v25_pilot_5_prog_*.stalled.tsv
rm -f batch_input_allofus.json batch_submission_ids.txt ordered_batch_ids.txt ct_submissions.txt
rm -f cromwell_submission_script_batch.sh cromwell_submission_script_individual_jobs.sh
rm -f options.json check_workflow_status.sh
rm -f "${outputFold}"/sample_list*.txt \
  "${outputFold}"/cram_file_list*.txt \
  "${outputFold}"/crai_file_list*.txt \
  "${outputFold}"/input_allofus*.json \
  "${outputFold}"/cromwell_submission_script_individual_jobs.sh

#### ENSURE NO STALE CROMWELL + RELEASE DB LOCK
log "Checking for running Cromwell."
if ps -ef | grep cromwell | grep -v grep | grep -q cromwell-91.jar; then
  log "Stopping existing Cromwell (cromwell-91.jar)."
  pkill -f cromwell-91.jar || true
fi
log "Cleaning Cromwell DB lock/tmp if no Cromwell is running."
if ! ps -ef | grep cromwell | grep -v grep | grep -q cromwell-91.jar; then
  rm -f local_cromwell_run.db.lck
  rm -rf local_cromwell_run.db.tmp
fi

#### BATCH CONFIG TEMPLATE (GCP Batch backend)
# NOTE: VPC network/subnetwork may need to be updated once AoU/Terra confirms exact names.
export BATCH_LOCATION="${BATCH_LOCATION:-us-central1}"
export PET_EMAIL="${PET_EMAIL:-pet-275664877747418b8b6ba@terra-vpc-sc-17dda7e1.iam.gserviceaccount.com}"
export VPC_NETWORK="${VPC_NETWORK:-projects/${GOOGLE_PROJECT}/global/networks/network}"
export VPC_SUBNETWORK="${VPC_SUBNETWORK:-projects/${GOOGLE_PROJECT}/regions/${BATCH_LOCATION}/subnetworks/subnetwork}"
export CROMWELL_BATCH_CONFIG_TEMPLATE="cromwell.batch.conf.template"
export CROMWELL_BATCH_CONFIG="cromwell.batch.conf"

log "Batch location resolved to: ${BATCH_LOCATION}"
log "VPC subnetwork resolved to: ${VPC_SUBNETWORK}"

log "Writing Cromwell Batch config template."
cat > "${CROMWELL_BATCH_CONFIG_TEMPLATE}" <<'EOF'
include required(classpath("application"))

google {
  application-name = "cromwell"
  auths = [{
    name = "application_default"
    scheme = "application_default"
  }]
}

system {
  new-workflow-poll-rate = 1
  max-concurrent-workflows = 10
  max-workflow-launch-count = 400
  job-rate-control {
    jobs = 50
    per = "3 seconds"
  }
}

backend {
  default = "GCPBATCH"
  providers {
    Local.config.root = "/dev/null"

    GCPBATCH {
      actor-factory = "cromwell.backend.google.batch.GcpBatchBackendLifecycleActorFactory"

      config {
        project = "__GOOGLE_PROJECT__"
        concurrent-job-limit = 10
        root = "__WORKSPACE_BUCKET__/workflows/cromwell-executions"

        virtual-private-cloud {
          network-name = "__VPC_NETWORK__"
          subnetwork-name = "__VPC_SUBNETWORK__"
        }

        batch {
          auth = "application_default"
          compute-service-account = "__PET_EMAIL__"
          location = "__BATCH_LOCATION__"
        }

        default-runtime-attributes {
          noAddress: true
        }

        filesystems {
          gcs {
            auth = "application_default"
          }
        }
      }
    }
  }
}

database {
  profile = "slick.jdbc.HsqldbProfile$"
  insert-batch-size = 6000
  db {
    driver = "org.hsqldb.jdbcDriver"
    url = "jdbc:hsqldb:file:local_cromwell_run.db;shutdown=false;hsqldb.default_table_type=cached;hsqldb.tx=mvcc;hsqldb.large_data=true;hsqldb.lob_compressed=true;hsqldb.script_format=3;hsqldb.result_max_memory_rows=20000"
    connectionTimeout = 300000
  }
}
EOF

log "Rendering Cromwell Batch config at ${CROMWELL_BATCH_CONFIG}."
sed \
  -e "s|__GOOGLE_PROJECT__|${GOOGLE_PROJECT}|g" \
  -e "s|__WORKSPACE_BUCKET__|${WORKSPACE_BUCKET}|g" \
  -e "s|__PET_EMAIL__|${PET_EMAIL}|g" \
  -e "s|__VPC_NETWORK__|${VPC_NETWORK}|g" \
  -e "s|__VPC_SUBNETWORK__|${VPC_SUBNETWORK}|g" \
  -e "s|__BATCH_LOCATION__|${BATCH_LOCATION}|g" \
  "${CROMWELL_BATCH_CONFIG_TEMPLATE}" > "${CROMWELL_BATCH_CONFIG}"


#### INSTALL DEPENDENCIES
# step 2: install dependecies pyhocon and clone repository.  a HOCON parser for Python
# note repo has a few broken links with file renames
if python - <<'PY' >/dev/null 2>&1
import pyhocon  # noqa: F401
PY
then
  log "Dependency already installed: pyhocon."
else
  log "Installing dependency: pyhocon."
  pip install pyhocon
fi
if [ ! -d "mtSwirl" ]; then
  log "Cloning mtSwirl repo."
  git clone https://github.com/rahulg603/mtSwirl.git
else
  log "mtSwirl repo already present, skipping clone."
fi


#### DOWNLOAD DATA
# step 4: download files if missing from repo 
# Note it might be redundant as files should already be in repo shouldnt they. perhaps main purpose is renaming??
download_if_missing() {
  local url="$1"
  local out="$2"
  if [ -f "$out" ]; then
    log "File already present, skipping download: $out"
  else
    log "Downloading $out"
    curl -L "$url" -o "$out"
  fi
}

validate_json_file() {
  local path="$1"
  python - <<PY >/dev/null 2>&1
import json
with open("${path}") as f:
    json.load(f)
PY
}

download_if_missing "https://raw.githubusercontent.com/rahulg603/mtSwirl/master/WDL/v2.5_MongoSwirl_Single/scatterWrapper_MitoPipeline_v2_5.wdl" "scatterWrapper_MitoPipeline_v2_5.wdl"
download_if_missing "https://raw.githubusercontent.com/rahulg603/mtSwirl/master/WDL/scripts/check_variant_bounds.R" "check_variant_bounds.R"
download_if_missing "https://raw.githubusercontent.com/rahulg603/mtSwirl/master/WDL/scripts/compatibilify_fa_intervals_consensus.R" "compatibilify_fa_intervals_consensus.R"
download_if_missing "https://raw.githubusercontent.com/rahulg603/mtSwirl/master/WDL/scripts/jsontools.py" "jsontools.py"
download_if_missing "https://raw.githubusercontent.com/rahulg603/mtSwirl/master/WDL/scripts/merge_per_batch.py" "merge_per_batch.py"
download_if_missing "https://raw.githubusercontent.com/rahulg603/mtSwirl/master/WDL/scripts/check_overlapping_homoplasmies.R" "check_overlapping_homoplasmies.R"
download_if_missing "https://raw.githubusercontent.com/rahulg603/mtSwirl/master/WDL/scripts/fix_liftover.py" "fix_liftover.py"
download_if_missing "https://raw.githubusercontent.com/rahulg603/mtSwirl/master/WDL/files/NUMTv3_all385.hg38.interval_list" "NUMTv3_all385.hg38.interval_list"
download_if_missing "https://raw.githubusercontent.com/rahulg603/mtSwirl/master/WDL/files/prepopulated_inputs.json" "input_allofus.json"
download_if_missing "https://github.com/genepi/haplocheck/releases/download/v1.3.3/haplocheck.zip" "haplocheck.zip"
if ! validate_json_file "input_allofus.json"; then
  log "input_allofus.json is not valid JSON; re-downloading."
  curl -L "https://raw.githubusercontent.com/rahulg603/mtSwirl/master/WDL/files/prepopulated_inputs.json" -o "input_allofus.json"
  if ! validate_json_file "input_allofus.json"; then
    log "ERROR: input_allofus.json is still invalid after re-download."
    exit 1
  fi
fi
# Use Cromwell release 91 (latest at time of retrieval, includes GCP Batch backend)
download_if_missing "https://github.com/broadinstitute/cromwell/releases/download/91/cromwell-91.jar" "cromwell-91.jar"

# Download matching WOMtool for the same version
download_if_missing "https://github.com/broadinstitute/cromwell/releases/download/91/womtool-91.jar" "womtool-91.jar"

if [ -d "${HOME}/.sdkman" ]; then
  log "sdkman already installed."
else
  download_if_missing "https://get.sdkman.io" "install_sdkman.sh"
  log "Installing sdkman."
  bash install_sdkman.sh
fi


#### CONFIGURE AND UPLOAD
sed -i 's|WORKSPACEDIR|'"$WORKSPACE_BUCKET|" input_allofus.json
sed -i 's|REQPAYS|'"$GOOGLE_PROJECT|" input_allofus.json


# step 5: write the input input_allofus.json
# input_allofus.json is the canonical, sample-agnostic input contract for the AoU mitochondrial WDL. It defines references, 
# scripts, tool behavior, and policy flags, and is programmatically cloned and augmented per batch with sample-specific 
# CRAM/CRAI inputs before submission to Cromwell.

python <<'PY'
import json

path = "input_allofus.json"
with open(path) as f:
    data = json.load(f)

fixed = {}
for k, v in data.items():
    if k.startswith("MitochondriaPipeline."):
        fixed["MitochondriaPipelineWrapper." + k.split(".", 1)[1]] = v
    else:
        fixed[k] = v

# Drop placeholder docker paths so WDL defaults are used.
fixed = {k: v for k, v in fixed.items() if v != "ADD_PATH_HERE"}

with open(path, "w") as f:
    json.dump(fixed, f)
print("Rewrote input_allofus.json with Wrapper keys and removed ADD_PATH_HERE placeholders.")
PY
echo ""
python - <<'PY'
import json, os

path = "input_allofus.json"
bucket = os.environ["WORKSPACE_BUCKET"].rstrip("/")
req_pays = os.environ.get("GOOGLE_PROJECT", "").strip()
gcs_numt = f"{bucket}/intervals/NUMTv3_all385.hg38.interval_list"
gcs_haplocheck = f"{bucket}/code/haplocheck.zip"
with open(path) as f:
    d = json.load(f)
d["MitochondriaPipelineWrapper.nuc_interval_list"] = gcs_numt
d["MitochondriaPipelineWrapper.haplocheck_zip"] = gcs_haplocheck
if req_pays:
    d["MitochondriaPipelineWrapper.requester_pays_project"] = req_pays
# Force a public base image to avoid docker registry auth failures.
d["MitochondriaPipelineWrapper.haplochecker_docker"] = "eclipse-temurin:17-jdk"
# Force all script inputs to GCS paths for Batch backend.
code_prefix = f"{bucket}/code"
script_keys = [
    "MitochondriaPipelineWrapper.CheckVariantBoundsScript",
    "MitochondriaPipelineWrapper.FaRenamingScript",
    "MitochondriaPipelineWrapper.CheckHomOverlapScript",
    "MitochondriaPipelineWrapper.HailLiftover",
    "MitochondriaPipelineWrapper.JsonTools",
    "MitochondriaPipelineWrapper.MergePerBatch",
]
for k in script_keys:
    if k in d and not str(d[k]).startswith("gs://"):
        d[k] = f"{code_prefix}/{d[k]}"
with open(path, "w") as f:
    json.dump(d, f)
print("Updated nuc_interval_list ->", gcs_numt)
print("Updated haplocheck_zip ->", gcs_haplocheck)
if req_pays:
    print("Updated requester_pays_project ->", req_pays)
print("Updated haplochecker_docker ->", d["MitochondriaPipelineWrapper.haplochecker_docker"])
PY
gsutil cp check_variant_bounds.R "$WORKSPACE_BUCKET"/code/
gsutil cp compatibilify_fa_intervals_consensus.R "$WORKSPACE_BUCKET"/code/
gsutil cp check_overlapping_homoplasmies.R "$WORKSPACE_BUCKET"/code/
gsutil cp fix_liftover.py "$WORKSPACE_BUCKET"/code/
gsutil cp merge_per_batch.py "$WORKSPACE_BUCKET"/code/
gsutil cp jsontools.py "$WORKSPACE_BUCKET"/code/
gsutil cp NUMTv3_all385.hg38.interval_list "$WORKSPACE_BUCKET"/intervals/
gsutil cp haplocheck.zip "$WORKSPACE_BUCKET"/code/
gsutil -u $GOOGLE_PROJECT cp $CDR_STORAGE_PATH/wgs/cram/manifest.csv .
gcloud auth list --format json | jq -r .[0].account


#### PREPARE FILESYSTEM
log "Preparing filesystem at ${outputFold}."
mkdir -p "${outputFold}"


#### MUNGE INPUTS AND PREPARE COMMANDS
log "Munging inputs and preparing Cromwell submission scripts."
wdl_in_use="$(pwd)/scatterWrapper_MitoPipeline_v2_5.wdl"
if [ -f "${wdl_in_use}" ]; then
  log "WDL in use: ${wdl_in_use}"
  if command -v sha256sum >/dev/null 2>&1; then
    log "WDL sha256: $(sha256sum "${wdl_in_use}" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    log "WDL sha256: $(shasum -a 256 "${wdl_in_use}" | awk '{print $1}')"
  else
    log "WDL checksum: sha256sum/shasum not available."
  fi
else
  log "WARNING: WDL not found at ${wdl_in_use}"
fi
python <<'CODE'
import os, re
import json
import pandas as pd
import shutil
from copy import deepcopy
from pyhocon import ConfigFactory, ConfigTree, HOCONConverter
from google.cloud import storage
import zipfile


# get globals
mem = int(os.getenv('USE_MEM'))
joblimit = int(os.getenv('JOBLIMIT'))
port = int(os.getenv('PORTID'))
n_test = int(os.getenv("numTest"))
n_iter = int(os.getenv("numIter"))
sql_db = os.getenv("SQL_DB_NAME")
batch_conf = os.getenv("CROMWELL_BATCH_CONFIG", "cromwell.batch.conf")
bucket = os.getenv("WORKSPACE_BUCKET")
project = os.getenv("GOOGLE_PROJECT")
tf_force_dl = os.getenv("FORCEDOWNLOAD") == 'True'
path_completed_samples = os.getenv("FILE_DONE")
path_failed_samples = os.getenv("FILE_FAIL")
tf_rerun_fail = os.getenv("RERUN_FAIL") == 'True'
path_indiv_save = os.getenv("outputFold") + '/'
 
# set up cromwell directories
cromwell_test_workdir = bucket + "/"  # Later, "cromwell-executions" will be appended to this for cromwell-workflow storage.
output_bucket = bucket + "/" + os.getenv("outputFold")  # This is where the output of the WDL will be.
 
print(f'Workspace bucket: {bucket}')
print(f'Workspace project: {project}')
print(f'Workspace cromwell working bucket: {cromwell_test_workdir}')
print(f'Workspace output bucket: {output_bucket}')

# grab list of completed and failed samples
bucket_name_str = re.sub('^gs://', '', bucket)
storage_client = storage.Client()
bucket_obj = storage_client.bucket(bucket_name_str)
if storage.Blob(bucket=bucket_obj, name=path_completed_samples).exists(storage_client):
    df_stats = pd.read_csv(f"gs://{bucket_name_str}/{path_completed_samples}", sep='\t')
    sample_list = list(df_stats.s)
else:
    sample_list = []
if storage.Blob(bucket=bucket_obj, name=path_failed_samples).exists(storage_client):
    df_failed = pd.read_csv(f"gs://{bucket_name_str}/{path_failed_samples}", sep='\t')
    sample_list_failed = list(df_failed.s)
else:
    sample_list_failed = []

# set up filenames
options_filename = "options.json"
wdl_filename = "scatterWrapper_MitoPipeline_v2_5.wdl"
json_filename = "input_allofus.json"
options_path = os.path.abspath(options_filename)
wdl_path = os.path.abspath(wdl_filename)
json_path = os.path.abspath(json_filename)
json_inputs = []

# Build WDL dependency zip so relative imports resolve on submission.
wdl_deps_zip = os.path.abspath("wdl_deps.zip")
wdl_deps_src = os.path.abspath("mtSwirl/WDL/v2.5_MongoSwirl_Single")
if not os.path.isdir(wdl_deps_src):
    raise ValueError(f"Expected WDL deps directory not found: {wdl_deps_src}")
with zipfile.ZipFile(wdl_deps_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(wdl_deps_src):
        for name in files:
            if name.endswith(".wdl"):
                full_path = os.path.join(root, name)
                rel_path = os.path.relpath(full_path, os.path.abspath("."))
                zf.write(full_path, rel_path)
print("Wrote WDL deps zip:", wdl_deps_zip)

# prefer curl by default; only use cromshell if explicitly enabled
use_cromshell = os.getenv("USE_CROMSHELL", "False") == "True"
cromshell_cmd = None
if use_cromshell:
    for candidate in ("cromshell-alpha", "cromshell"):
        if shutil.which(candidate):
            cromshell_cmd = candidate
            break
    if cromshell_cmd is None:
        raise ValueError("USE_CROMSHELL=True but cromshell is not available on PATH.")

# create options file
# options_content = f'{{\n  "jes_gcs_root": "{output_bucket}",\n  "workflow_failure_mode": "NoNewCalls"\n}}\n'
options_content = f'{{\n  "jes_gcs_root": "{output_bucket}"\n}}\n'

fp = open(options_filename, 'w')
fp.write(options_content)
fp.close()
print(options_content)

# create cromwell configuration, lifting the job limit and exporting to local SQL database
with open('/home/jupyter/cromwell.conf', 'r') as f:
    input_conf = f.read()
include_str_repl = 'include required(classpath("application"))\n\n'
input_conf_rm = input_conf.replace(include_str_repl, '')
cromwell_config_file = ConfigFactory.parse_string(input_conf_rm)
cromwell_config_file['system'] = ConfigTree({'new-workflow-poll-rate': 1,
                                             'max-concurrent-workflows': joblimit,
                                             'max-workflow-launch-count': 400,
                                             'job-rate-control': ConfigTree({'jobs': 50,
                                                                             'per': '3 seconds'})})
cromwell_config_file['backend']['providers']['PAPIv2-beta']['config']['concurrent-job-limit'] = joblimit
cromwell_config_file['backend']['providers']['PAPIv2-beta']['config']['genomics']['enable-fuse'] = True
cromwell_config_file['database'] = ConfigTree({'profile': "slick.jdbc.HsqldbProfile$",
                                               'insert-batch-size': 6000,
                                               'db': ConfigTree({'driver':"org.hsqldb.jdbcDriver", 
                                                                 'url':f'jdbc:hsqldb:file:{sql_db};shutdown=false;hsqldb.default_table_type=cached;hsqldb.tx=mvcc;hsqldb.large_data=true;hsqldb.lob_compressed=true;hsqldb.script_format=3;hsqldb.result_max_memory_rows=20000',
                                                                 'connectionTimeout': 300000})})
with open('/home/jupyter/cromwell.new.conf', 'w') as f:
    f.write(include_str_repl + HOCONConverter.to_hocon(cromwell_config_file))

# load cromwell configuration for modification
with open(json_path, 'r') as json_file:
    jf = json.load(json_file)

# generate workflows and cromwell commands
df = pd.read_csv('manifest.csv')
original_size = df.shape[0]
df = df[~df.person_id.isin(sample_list)]
if tf_rerun_fail:
    df = df[df.person_id.isin(sample_list_failed)]
    new_size = df.shape[0]
    if not all(x in [x in list(df.person_id) for x in sample_list_failed]):
        raise ValueError("ERROR: All failed samples should be found in the sample list.")
    print(f'{str(new_size)} previously failed samples added to list for rerunning.')
else:
    df = df[~df.person_id.isin(sample_list_failed)]
    new_size = df.shape[0]
    if original_size-new_size != len(sample_list)+len(sample_list_failed):
        raise ValueError("ERROR: the number of samples removed from manifest must be the same as the number of processed samples + number of prior failures.")
    print(f'{str(len(sample_list) + len(sample_list_failed))} samples already processed or failed and removed from manifest.')
    print(f'{str(new_size)} samples remain in the manifest (of {str(original_size)} originally present).')
df = df.reset_index(drop=True)

cromwell_run_cmd = f'source "/home/jupyter/.sdkman/bin/sdkman-init.sh" && sdk install java 17.0.8-tem && sdk use java 17.0.8-tem && echo "Validating WDL..." && java -jar womtool-91.jar validate _WDL_FILE_ && java -Xmx{str(mem)}g -classpath ".:sqlite-jdbc.jar" -Dconfig.file={batch_conf} -Dwebservice.port={str(port)} -jar cromwell-91.jar server'
cromwell_run_cmd_final = cromwell_run_cmd.replace("_WDL_FILE_", wdl_path)

with open(f"cromwell_startup_script.sh", "w") as text_file:
    text_file.write("#!/bin/bash\n")
    text_file.write(cromwell_run_cmd_final + '\n')

with open(f"cromwell_submission_script_individual_jobs.sh", "w") as text_file:
    text_file.write("#!/bin/bash\n")

json_collection = []
max_rows = df.shape[0]

for idx in range(0, n_iter):

    if (idx+1)*n_test >= max_rows:
        this_max = max_rows
        break_here = True
    else:
        this_max = (idx+1)*n_test
        break_here = False
    
    df_sub = df.iloc[idx*n_test: this_max]
    s = list(df_sub.person_id)
    cram_paths = list(df_sub.cram_uri)
    crai_paths = list(df_sub.cram_index_uri)

    f = open(f"{path_indiv_save}sample_list{str(idx)}.txt", "w")
    f.writelines('\n'.join([str(x) for x in s]) + '\n')
    f.close()

    f = open(f"{path_indiv_save}cram_file_list{str(idx)}.txt", "w")
    f.writelines('\n'.join(cram_paths) + '\n')
    f.close()

    f = open(f"{path_indiv_save}crai_file_list{str(idx)}.txt", "w")
    f.writelines('\n'.join(crai_paths) + '\n')
    f.close()

    dct_update = {'MitochondriaPipelineWrapper.wgs_aligned_input_bam_or_cram_list': f"{path_indiv_save}cram_file_list{str(idx)}.txt",
                  'MitochondriaPipelineWrapper.wgs_aligned_input_bam_or_cram_index_list': f"{path_indiv_save}crai_file_list{str(idx)}.txt",
                  'MitochondriaPipelineWrapper.sample_name_list': f"{path_indiv_save}sample_list{str(idx)}.txt",
                  'MitochondriaPipelineWrapper.force_manual_download': tf_force_dl}

    this_json = deepcopy(jf)
    this_json.update(dct_update)
    json_collection.append(this_json)

    this_json_filename = f"input_allofus{str(idx)}.json"
    this_json_path = os.path.abspath(path_indiv_save + this_json_filename)
    with open(this_json_path, 'w') as f:
        json.dump(this_json, f)
    json_inputs.append(this_json_path)

    this_cromwell_cmd = f'curl -X POST "http://localhost:{str(port)}/api/workflows/v1" -H "accept: application/json" -F workflowSource=@_WDL_FILE_ -F workflowInputs=@_INPUTS_ -F workflowOptions=@_OPTIONS_FILE_ -F workflowDependencies=@_DEPS_FILE_'
    this_cromwell_cmd = this_cromwell_cmd.replace("_WDL_FILE_", wdl_path)
    this_cromwell_cmd = this_cromwell_cmd.replace("_INPUTS_", this_json_path)
    this_cromwell_cmd = this_cromwell_cmd.replace("_OPTIONS_FILE_", options_path)
    this_cromwell_cmd = this_cromwell_cmd.replace("_DEPS_FILE_", wdl_deps_zip)

    with open(f"{path_indiv_save}cromwell_submission_script_individual_jobs.sh", "a") as text_file:
        text_file.write(this_cromwell_cmd + '\n')

    if break_here:
        break

batch_json_filename = f"batch_input_allofus.json"
batch_json_path = os.path.abspath(batch_json_filename)
with open(batch_json_path, 'w') as f:
    json.dump(json_collection, f)
    
with open('ct_submissions.txt', 'w') as f:
    f.write(str(len(json_collection)))

batch_cromwell_cmd = f'curl -X POST "http://localhost:{str(port)}/api/workflows/v1/batch" -H "accept: application/json" -F workflowSource=@_WDL_FILE_ -F workflowInputs=@_INPUTS_ -F workflowOptions=@_OPTIONS_FILE_ -F workflowDependencies=@_DEPS_FILE_'
batch_cromwell_cmd = batch_cromwell_cmd.replace("_WDL_FILE_", wdl_path)
batch_cromwell_cmd = batch_cromwell_cmd.replace("_INPUTS_", batch_json_path)
batch_cromwell_cmd = batch_cromwell_cmd.replace("_OPTIONS_FILE_", options_path)
batch_cromwell_cmd = batch_cromwell_cmd.replace("_DEPS_FILE_", wdl_deps_zip)

count_n_submit = "submission_count=$(grep -o 'Submitted' batch_submission_ids.txt | wc -l)\n"
test_ct = 'if [ "$submission_count" -ne "$(cat ct_submissions.txt)" ]; then echo "ERROR: submission count is incorrect."; exit 1; fi\n'
get_batch_ids = 'cat batch_submission_ids.txt | sed \'s/{"id"://g\' | sed \'s/","status":"Submitted"}//g\' | sed \'s/"//g\' | sed \'s/,/\\n/g\' | sed \'s/\\[//g\' | sed \'s/\\]//g\' > ordered_batch_ids.txt\n'

with open(f"cromwell_submission_script_batch.sh", "w") as text_file:
    text_file.write("#!/bin/bash\n")
    if use_cromshell:
        text_file.write('set -e\n')
        text_file.write('> batch_submission_ids.txt\n')
        text_file.write('> ordered_batch_ids.txt\n')
        for inp in json_inputs:
            text_file.write(f'{cromshell_cmd} submit {wdl_path} {inp} --options-json {options_path} | tee -a batch_submission_ids.txt\n')
        text_file.write("cat batch_submission_ids.txt | jq -r '.id' > ordered_batch_ids.txt\n")
        text_file.write('echo \"\" >> ordered_batch_ids.txt\n')
    else:
        text_file.write('set -e\n')
        text_file.write('> batch_submission_ids.txt\n')
        text_file.write('> ordered_batch_ids.txt\n')
        text_file.write(batch_cromwell_cmd + ' | tee batch_submission_ids.txt\n')
        text_file.write(count_n_submit)
        text_file.write(test_ct)
        text_file.write(get_batch_ids)
        text_file.write('echo \"\" >> ordered_batch_ids.txt\n')

CODE
log "Munge/prepare step complete."


#### LAUNCH SERVER AS A SUBPROCESS
log "Launching Cromwell server (Batch config) in background."
chmod 777 cromwell_startup_script.sh
setsid ./cromwell_startup_script.sh > cromwell_server_stdout.log 2>cromwell_server_stderr.log &


#### CREATE MONITORING COMMAND
sleep 150
log "Server started."
log "Here is the tail of the current stdout.log. Examine this to make sure the server is running:"
tail -n10 cromwell_server_stdout.log
echo ""
log "Run cromwell_submission_script_batch.sh to submit the desired jobs."
echo ""
log "Run the following command to track the progress of the various runs:"
echo ""
export success_file_pref="${outputFold}_prog_$(date +'%T' | sed 's|:|.|g')"
cat > check_workflow_status.sh <<EOS
#!/bin/bash
set -e
output_fold="${outputFold}"
success_file_pref="${success_file_pref}"
if [ ! -s "ordered_batch_ids.txt" ]; then
  echo "ERROR: ordered_batch_ids.txt is missing or empty. Run cromwell_submission_script_batch.sh first."
  exit 1
fi
echo "Using batch IDs:"
cat ordered_batch_ids.txt
echo ""
echo "Cromwell status/metadata (per workflow ID):"
while IFS= read -r wf_id; do
  if [ -z "\${wf_id}" ]; then
    continue
  fi
  echo "---------------------------------"
  echo "Workflow ID: \${wf_id}"
  echo "Status curl:"
  echo "  curl -s \"http://localhost:${PORTID}/api/workflows/v1/\${wf_id}/status\""
  curl -s "http://localhost:${PORTID}/api/workflows/v1/\${wf_id}/status" || true
  echo ""
  echo "Failures curl:"
  echo "  curl -s \"http://localhost:${PORTID}/api/workflows/v1/\${wf_id}/metadata?includeKey=failures\""
  if command -v jq >/dev/null 2>&1; then
    curl -s "http://localhost:${PORTID}/api/workflows/v1/\${wf_id}/metadata?includeKey=failures" | jq . || true
  else
    curl -s "http://localhost:${PORTID}/api/workflows/v1/\${wf_id}/metadata?includeKey=failures" || true
  fi
  echo ""
done < ordered_batch_ids.txt
echo ""
python mtSwirl/generate_mtdna_call_mt/AoU/cromwell_run_monitor.py --run-folder "\${output_fold}" --sub-ids ordered_batch_ids.txt --sample-lists "\${output_fold}/sample_list{}.txt" --check-success --output "\${success_file_pref}"
EOS
chmod +x check_workflow_status.sh
echo ""
log "We have outputted this command in check_workflow_status.sh."
echo ""


#### CREATE UPLOADING COMMAND
log "Preparing compile_paths.sh for post-run uploads."
echo "Upon completion of the workflow, don't forget to upload data file paths to gs:// !!"
echo "Use compile_paths.sh to do this, which will both merge files from this run and append to the database."
echo '#!/bin/bash' > compile_paths.sh
export tsvPREF="${WORKSPACE_BUCKET}/tsv/${outputFold}"
export htPREF="${WORKSPACE_BUCKET}/ht/${outputFold}"
echo "gsutil cp ${success_file_pref}'*' ${tsvPREF}/" >> compile_paths.sh
echo "python mtSwirl/generate_mtdna_call_mt/AoU/aou_collate_tables.py --pipeline-output-path ${success_file_pref}.success.tsv --file-paths-table-flat-output ${tsvPREF}/tab_batch_file_paths.tsv --per-sample-stats-flat-output ${tsvPREF}/tab_per_sample_stats.tsv --file-paths-table-output ${htPREF}/tab_batch_file_paths.ht --per-sample-stats-output ${htPREF}/tab_per_sample_stats.ht" >> compile_paths.sh
echo "python mtSwirl/generate_mtdna_call_mt/AoU/aou_update_sample_database.py --new-paths tsv/${outputFold}/tab_batch_file_paths.tsv --new-stats tsv/${outputFold}/tab_per_sample_stats.tsv --new-failures tsv/${outputFold}/${success_file_pref}.failure.tsv" >> compile_paths.sh
echo "" >> compile_paths.sh
log "compile_paths.sh written."
