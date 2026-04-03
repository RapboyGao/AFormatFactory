use base64::Engine;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};
use tauri::Emitter;
use tauri::Manager;
use uuid::Uuid;

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct AffProgress {
    processed_frames: u64,
    processed_time_seconds: f64,
    estimated_ratio: f64,
    bitrate_kbps: f64,
    speed: f64,
}

#[allow(non_camel_case_types)]
type AFFOpaqueJob = c_void;

type AFFLogCallback = Option<extern "C" fn(c_int, *const c_char, *mut c_void)>;
type AFFProgressCallback = Option<extern "C" fn(AffProgress, *mut c_void)>;

unsafe extern "C" {
    fn aff_create_job() -> *mut AFFOpaqueJob;
    fn aff_destroy_job(job: *mut AFFOpaqueJob);
    fn aff_set_input_output(job: *mut AFFOpaqueJob, input_path: *const c_char, output_path: *const c_char, overwrite_existing: c_int) -> c_int;
    fn aff_set_arguments(job: *mut AFFOpaqueJob, arguments: *const *const c_char, argument_count: c_int) -> c_int;
    fn aff_set_media_edit_inputs(job: *mut AFFOpaqueJob, additional_audio_input: *const c_char, subtitle_input: *const c_char, subtitle_codec: *const c_char) -> c_int;
    fn aff_add_metadata(job: *mut AFFOpaqueJob, key: *const c_char, value: *const c_char) -> c_int;
    fn aff_clear_chapters(job: *mut AFFOpaqueJob) -> c_int;
    fn aff_add_chapter(job: *mut AFFOpaqueJob, start_milliseconds: i64, end_milliseconds: i64, title: *const c_char) -> c_int;
    fn aff_run_job_async(job: *mut AFFOpaqueJob, log_callback: AFFLogCallback, progress_callback: AFFProgressCallback, context: *mut c_void) -> c_int;
    fn aff_cancel_job(job: *mut AFFOpaqueJob) -> c_int;
    fn aff_detect_capabilities(muxers_json: *mut *mut c_char, encoders_json: *mut *mut c_char) -> c_int;
    fn aff_copy_last_error() -> *const c_char;
    fn aff_free_string(value: *mut c_char);
}

#[derive(Debug, Serialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
enum TaskStatus {
    Queued,
    Running,
    Success,
    Failed,
    Cancelled,
}

#[derive(Debug, Serialize, Clone, Default)]
struct TaskProgress {
    processed_frames: u64,
    processed_time_seconds: f64,
    estimated_ratio: f64,
    bitrate_kbps: f64,
    speed: f64,
}

#[derive(Debug, Serialize, Clone)]
struct QueueTask {
    id: String,
    domain: String,
    input: String,
    output: String,
    format: String,
    status: TaskStatus,
    error: Option<String>,
    created_at: String,
    updated_at: String,
    progress: TaskProgress,
}

#[derive(Debug, Deserialize, Clone)]
struct ConversionTaskDraft {
    domain: String,
    input: String,
    output: String,
    format: String,
    overwrite: bool,
    args: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct MediaEditChapter {
    start_ms: i64,
    end_ms: i64,
    title: String,
}

#[derive(Debug, Deserialize)]
struct MediaEditRequest {
    input: String,
    output: String,
    overwrite: bool,
    metadata: HashMap<String, String>,
    chapters: Vec<MediaEditChapter>,
    additional_audio_input: Option<String>,
    subtitle_input: Option<String>,
    subtitle_codec: Option<String>,
}

#[derive(Debug, Serialize)]
struct Capabilities {
    muxers: Vec<String>,
    encoders: Vec<String>,
}

#[derive(Debug, Serialize)]
struct ImagePreviewResult {
    preview_data_url: String,
    file_size_bytes: u64,
}

struct RuntimeTask {
    ui: QueueTask,
    draft: ConversionTaskDraft,
    job_ptr: usize,
}

struct QueueState {
    tasks: Vec<RuntimeTask>,
    started: bool,
    running_workers: usize,
    scheduler_spawned: bool,
    concurrency: usize,
}

impl QueueState {
    fn new() -> Self {
        Self {
            tasks: Vec::new(),
            started: false,
            running_workers: 0,
            scheduler_spawned: false,
            concurrency: num_cpus::get().max(1),
        }
    }
}

#[derive(Clone)]
struct SharedState {
    queue: Arc<Mutex<QueueState>>,
    logs: Arc<Mutex<Vec<String>>>,
}

impl SharedState {
    fn new() -> Self {
        Self {
            queue: Arc::new(Mutex::new(QueueState::new())),
            logs: Arc::new(Mutex::new(Vec::new())),
        }
    }

    fn push_log(&self, line: impl Into<String>) {
        let mut logs = self.logs.lock().expect("logs poisoned");
        logs.push(line.into());
        if logs.len() > 2000 {
            let drain = logs.len() - 2000;
            logs.drain(0..drain);
        }
    }
}

struct CallbackCtx {
    shared: SharedState,
    task_id: String,
}

fn now_iso() -> String {
    let secs = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_secs();
    format!("{secs}")
}

fn last_error() -> String {
    unsafe {
        let ptr = aff_copy_last_error();
        if ptr.is_null() {
            return "unknown error".to_string();
        }
        CStr::from_ptr(ptr).to_string_lossy().to_string()
    }
}

fn cstring(value: &str) -> Result<CString, String> {
    CString::new(value).map_err(|_| format!("string contains null byte: {value}"))
}

fn sanitized_file_stem(path: &Path) -> String {
    path.file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("image")
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '_' })
        .collect()
}

fn preview_output_path(app: &tauri::AppHandle, input: &Path) -> Result<PathBuf, String> {
    let metadata = std::fs::metadata(input).map_err(|err| err.to_string())?;
    let modified = metadata
        .modified()
        .ok()
        .and_then(|value| value.duration_since(SystemTime::UNIX_EPOCH).ok())
        .map(|value| value.as_secs())
        .unwrap_or(0);

    let preview_dir = app
        .path()
        .app_cache_dir()
        .map_err(|err| err.to_string())?
        .join("image-preview");
    std::fs::create_dir_all(&preview_dir).map_err(|err| err.to_string())?;
    Ok(preview_dir.join(format!(
        "{}-{}-{}.jpg",
        sanitized_file_stem(input),
        metadata.len(),
        modified
    )))
}

fn set_task_status(shared: &SharedState, task_id: &str, status: TaskStatus, error: Option<String>) {
    let mut queue = shared.queue.lock().expect("queue poisoned");
    if let Some(task) = queue.tasks.iter_mut().find(|t| t.ui.id == task_id) {
        task.ui.status = status;
        task.ui.error = error;
        task.ui.updated_at = now_iso();
    }
}

extern "C" fn log_callback(_level: c_int, message: *const c_char, context: *mut c_void) {
    if context.is_null() || message.is_null() {
        return;
    }
    let ctx = unsafe { &*(context as *const CallbackCtx) };
    let line = unsafe { CStr::from_ptr(message).to_string_lossy().to_string() };
    if line.trim().is_empty() {
        return;
    }
    if line.contains("error") || line.contains("Error") {
        ctx.shared.push_log(format!("[{}] {}", ctx.task_id, line));
    }
}

extern "C" fn progress_callback(progress: AffProgress, context: *mut c_void) {
    if context.is_null() {
        return;
    }
    let ctx = unsafe { &*(context as *const CallbackCtx) };
    let mut queue = ctx.shared.queue.lock().expect("queue poisoned");
    if let Some(task) = queue.tasks.iter_mut().find(|t| t.ui.id == ctx.task_id) {
        task.ui.progress = TaskProgress {
            processed_frames: progress.processed_frames,
            processed_time_seconds: progress.processed_time_seconds,
            estimated_ratio: progress.estimated_ratio,
            bitrate_kbps: progress.bitrate_kbps,
            speed: progress.speed,
        };
        task.ui.updated_at = now_iso();
    }
}

fn run_conversion_task(shared: SharedState, task_id: String) {
    let draft = {
        let mut queue = shared.queue.lock().expect("queue poisoned");
        let Some(task) = queue.tasks.iter_mut().find(|t| t.ui.id == task_id) else {
            return;
        };
        task.ui.status = TaskStatus::Running;
        task.ui.updated_at = now_iso();
        task.draft.clone()
    };

    let input = match cstring(&draft.input) {
        Ok(v) => v,
        Err(e) => {
            set_task_status(&shared, &task_id, TaskStatus::Failed, Some(e));
            return;
        }
    };
    let output = match cstring(&draft.output) {
        Ok(v) => v,
        Err(e) => {
            set_task_status(&shared, &task_id, TaskStatus::Failed, Some(e));
            return;
        }
    };

    let mut arg_cstr = Vec::with_capacity(draft.args.len());
    for arg in &draft.args {
        match cstring(arg) {
            Ok(v) => arg_cstr.push(v),
            Err(e) => {
                set_task_status(&shared, &task_id, TaskStatus::Failed, Some(e));
                return;
            }
        }
    }
    let arg_ptrs: Vec<*const c_char> = arg_cstr.iter().map(|x| x.as_ptr()).collect();

    let job = unsafe { aff_create_job() };
    if job.is_null() {
        set_task_status(&shared, &task_id, TaskStatus::Failed, Some(last_error()));
        return;
    }

    {
        let mut queue = shared.queue.lock().expect("queue poisoned");
        if let Some(task) = queue.tasks.iter_mut().find(|t| t.ui.id == task_id) {
            task.job_ptr = job as usize;
        }
    }

    let prepare_ok = unsafe {
        aff_set_input_output(job, input.as_ptr(), output.as_ptr(), if draft.overwrite { 1 } else { 0 }) == 0
            && aff_set_arguments(job, arg_ptrs.as_ptr(), arg_ptrs.len() as c_int) == 0
    };

    if !prepare_ok {
        let err = last_error();
        unsafe { aff_destroy_job(job) };
        set_task_status(&shared, &task_id, TaskStatus::Failed, Some(err));
        return;
    }

    let callback_ctx = Box::new(CallbackCtx {
        shared: shared.clone(),
        task_id: task_id.clone(),
    });
    let callback_ptr = Box::into_raw(callback_ctx) as *mut c_void;

    let result = unsafe { aff_run_job_async(job, Some(log_callback), Some(progress_callback), callback_ptr) };

    unsafe {
        drop(Box::from_raw(callback_ptr as *mut CallbackCtx));
        aff_destroy_job(job);
    }

    {
        let mut queue = shared.queue.lock().expect("queue poisoned");
        if let Some(task) = queue.tasks.iter_mut().find(|t| t.ui.id == task_id) {
            task.job_ptr = 0;
            task.ui.updated_at = now_iso();
            let final_status = if result == 0 {
                TaskStatus::Success
            } else {
                let msg = last_error();
                if msg.contains("cancelled") {
                    TaskStatus::Cancelled
                } else {
                    task.ui.error = Some(msg);
                    TaskStatus::Failed
                }
            };
            task.ui.status = final_status;
            if matches!(final_status, TaskStatus::Success) {
                task.ui.progress.estimated_ratio = 1.0;
            }
        }
        if queue.running_workers > 0 {
            queue.running_workers -= 1;
        }
    }
}

async fn scheduler_loop(shared: SharedState) {
    loop {
        let mut spawn_ids: Vec<String> = Vec::new();
        {
            let mut queue = shared.queue.lock().expect("queue poisoned");
            if !queue.started {
                break;
            }

            while queue.running_workers < queue.concurrency {
                let next = queue
                    .tasks
                    .iter()
                    .find(|t| t.ui.status == TaskStatus::Queued)
                    .map(|t| t.ui.id.clone());
                let Some(id) = next else { break };
                queue.running_workers += 1;
                spawn_ids.push(id);
            }
        }

        for id in spawn_ids {
            let shared_clone = shared.clone();
            tauri::async_runtime::spawn_blocking(move || run_conversion_task(shared_clone, id));
        }

        tokio::time::sleep(Duration::from_millis(200)).await;
    }

    let mut queue = shared.queue.lock().expect("queue poisoned");
    queue.scheduler_spawned = false;
}

#[tauri::command]
fn create_tasks(state: tauri::State<'_, SharedState>, drafts: Vec<ConversionTaskDraft>) -> Result<usize, String> {
    let mut queue = state.queue.lock().expect("queue poisoned");
    let now = now_iso();
    for draft in drafts.iter() {
        let id = Uuid::new_v4().to_string();
        queue.tasks.push(RuntimeTask {
            ui: QueueTask {
                id,
                domain: draft.domain.clone(),
                input: draft.input.clone(),
                output: draft.output.clone(),
                format: draft.format.clone(),
                status: TaskStatus::Queued,
                error: None,
                created_at: now.clone(),
                updated_at: now.clone(),
                progress: TaskProgress::default(),
            },
            draft: draft.clone(),
            job_ptr: 0,
        });
    }
    Ok(drafts.len())
}

#[tauri::command]
fn list_tasks(state: tauri::State<'_, SharedState>) -> Vec<QueueTask> {
    let queue = state.queue.lock().expect("queue poisoned");
    queue.tasks.iter().map(|t| t.ui.clone()).collect()
}

#[tauri::command]
fn start_queue(app: tauri::AppHandle, state: tauri::State<'_, SharedState>) {
    let mut queue = state.queue.lock().expect("queue poisoned");
    queue.started = true;
    if queue.scheduler_spawned {
        return;
    }
    queue.scheduler_spawned = true;
    let shared = state.inner().clone();
    drop(queue);

    tauri::async_runtime::spawn(async move {
        scheduler_loop(shared.clone()).await;
        let _ = app.emit("queue-stopped", ());
    });
}

#[tauri::command]
fn cancel_task(state: tauri::State<'_, SharedState>, id: String) -> Result<(), String> {
    let mut queue = state.queue.lock().expect("queue poisoned");
    let Some(task) = queue.tasks.iter_mut().find(|t| t.ui.id == id) else {
        return Err("task not found".to_string());
    };

    if task.ui.status == TaskStatus::Queued {
        task.ui.status = TaskStatus::Cancelled;
        task.ui.updated_at = now_iso();
        return Ok(());
    }

    if task.ui.status == TaskStatus::Running && task.job_ptr != 0 {
        let job_ptr = task.job_ptr as *mut AFFOpaqueJob;
        let cancelled = unsafe { aff_cancel_job(job_ptr) == 0 };
        if cancelled {
            return Ok(());
        }
        return Err(last_error());
    }
    Ok(())
}

#[tauri::command]
fn delete_task(state: tauri::State<'_, SharedState>, id: String) -> Result<(), String> {
    let mut queue = state.queue.lock().expect("queue poisoned");
    let Some(index) = queue.tasks.iter().position(|t| t.ui.id == id) else {
        return Err("task not found".to_string());
    };
    if queue.tasks[index].ui.status == TaskStatus::Running {
        return Err("running task cannot be deleted".to_string());
    }
    queue.tasks.remove(index);
    Ok(())
}

#[tauri::command]
fn clear_completed(state: tauri::State<'_, SharedState>) {
    let mut queue = state.queue.lock().expect("queue poisoned");
    queue.tasks.retain(|t| matches!(t.ui.status, TaskStatus::Queued | TaskStatus::Running));
}

#[tauri::command]
fn set_concurrency(state: tauri::State<'_, SharedState>, value: usize) {
    let mut queue = state.queue.lock().expect("queue poisoned");
    queue.concurrency = value.max(1);
}

#[tauri::command]
fn get_concurrency(state: tauri::State<'_, SharedState>) -> usize {
    let queue = state.queue.lock().expect("queue poisoned");
    queue.concurrency
}

#[tauri::command]
fn pick_input_files() -> Vec<String> {
    rfd::FileDialog::new()
        .pick_files()
        .unwrap_or_default()
        .into_iter()
        .map(|p| p.to_string_lossy().to_string())
        .collect()
}

#[tauri::command]
fn pick_image_files() -> Vec<String> {
    rfd::FileDialog::new()
        .add_filter("HEIF Images", &["heic", "heif", "hif"])
        .pick_files()
        .unwrap_or_default()
        .into_iter()
        .map(|p| p.to_string_lossy().to_string())
        .collect()
}

#[tauri::command]
fn pick_output_directory() -> Option<String> {
    rfd::FileDialog::new()
        .pick_folder()
        .map(|p| p.to_string_lossy().to_string())
}

#[tauri::command]
fn render_image_preview(app: tauri::AppHandle, input_path: String) -> Result<ImagePreviewResult, String> {
    let input = PathBuf::from(&input_path);
    if !input.exists() {
        return Err("input image not found".to_string());
    }

    let output = preview_output_path(&app, &input)?;
    let status = Command::new("sips")
        .arg("-s")
        .arg("format")
        .arg("jpeg")
        .arg(&input)
        .arg("--out")
        .arg(&output)
        .status()
        .map_err(|err| err.to_string())?;

    if !status.success() {
        return Err("failed to render image preview".to_string());
    }

    let bytes = std::fs::read(&output).map_err(|err| err.to_string())?;
    let preview_data_url = format!(
        "data:image/jpeg;base64,{}",
        base64::engine::general_purpose::STANDARD.encode(bytes)
    );
    let file_size_bytes = std::fs::metadata(&input).map_err(|err| err.to_string())?.len();
    Ok(ImagePreviewResult {
        preview_data_url,
        file_size_bytes,
    })
}

#[tauri::command]
fn export_images_as_jpeg(input_paths: Vec<String>) -> Result<Vec<String>, String> {
    if input_paths.is_empty() {
        return Err("no input images selected".to_string());
    }

    let first_input = PathBuf::from(&input_paths[0]);
    let output_dir = rfd::FileDialog::new()
        .set_directory(first_input.parent().unwrap_or_else(|| Path::new("/")))
        .pick_folder()
        .ok_or_else(|| "export cancelled".to_string())?;

    let mut outputs = Vec::new();
    for input_path in input_paths {
        let input = PathBuf::from(&input_path);
        if !input.exists() {
            continue;
        }

        let file_stem = input
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or("image");
        let output = output_dir.join(format!("{file_stem}.jpg"));

        #[cfg(target_os = "macos")]
        {
            let status = Command::new("sips")
                .arg("-s")
                .arg("format")
                .arg("jpeg")
                .arg(&input)
                .arg("--out")
                .arg(&output)
                .status()
                .map_err(|err| err.to_string())?;

            if !status.success() {
                return Err(format!("failed to export JPEG: {}", input.display()));
            }
        }

        #[cfg(not(target_os = "macos"))]
        {
            return Err("HEIF JPEG export is currently only implemented on macOS".to_string());
        }

        outputs.push(output.to_string_lossy().to_string());
    }

    Ok(outputs)
}

#[tauri::command]
fn reorder_tasks(state: tauri::State<'_, SharedState>, ordered_ids: Vec<String>) -> Result<(), String> {
    let mut queue = state.queue.lock().expect("queue poisoned");
    if queue.running_workers > 0 {
        return Err("queue is running; cannot reorder".to_string());
    }

    if ordered_ids.len() != queue.tasks.len() {
        return Err("ordered_ids length mismatch".to_string());
    }

    let mut remaining = std::mem::take(&mut queue.tasks);
    let mut reordered = Vec::with_capacity(remaining.len());
    for id in ordered_ids {
        let Some(idx) = remaining.iter().position(|t| t.ui.id == id) else {
            return Err("ordered_ids contains unknown task id".to_string());
        };
        reordered.push(remaining.remove(idx));
    }
    if !remaining.is_empty() {
        return Err("ordered_ids did not consume all tasks".to_string());
    }
    queue.tasks = reordered;
    Ok(())
}

#[tauri::command]
fn detect_capabilities() -> Result<Capabilities, String> {
    let mut muxers_ptr: *mut c_char = std::ptr::null_mut();
    let mut encoders_ptr: *mut c_char = std::ptr::null_mut();
    let ok = unsafe { aff_detect_capabilities(&mut muxers_ptr, &mut encoders_ptr) == 0 };
    if !ok {
        return Err(last_error());
    }
    if muxers_ptr.is_null() || encoders_ptr.is_null() {
        return Err("capability probe returned null pointer".to_string());
    }

    let muxers_json = unsafe { CStr::from_ptr(muxers_ptr).to_string_lossy().to_string() };
    let encoders_json = unsafe { CStr::from_ptr(encoders_ptr).to_string_lossy().to_string() };

    unsafe {
        aff_free_string(muxers_ptr);
        aff_free_string(encoders_ptr);
    }

    let muxers: Vec<String> = serde_json::from_str(&muxers_json).map_err(|e| e.to_string())?;
    let encoders: Vec<String> = serde_json::from_str(&encoders_json).map_err(|e| e.to_string())?;
    Ok(Capabilities { muxers, encoders })
}

#[tauri::command]
fn run_media_edit(request: MediaEditRequest) -> Result<(), String> {
    let job = unsafe { aff_create_job() };
    if job.is_null() {
        return Err(last_error());
    }

    let input = cstring(&request.input)?;
    let output = cstring(&request.output)?;

    let mut additional_audio_c = None;
    let mut subtitle_input_c = None;
    let mut subtitle_codec_c = None;

    let additional_audio_ptr = if let Some(v) = &request.additional_audio_input {
        additional_audio_c = Some(cstring(v)?);
        additional_audio_c.as_ref().map_or(std::ptr::null(), |x| x.as_ptr())
    } else {
        std::ptr::null()
    };

    let subtitle_input_ptr = if let Some(v) = &request.subtitle_input {
        subtitle_input_c = Some(cstring(v)?);
        subtitle_input_c.as_ref().map_or(std::ptr::null(), |x| x.as_ptr())
    } else {
        std::ptr::null()
    };

    let subtitle_codec_ptr = if let Some(v) = &request.subtitle_codec {
        subtitle_codec_c = Some(cstring(v)?);
        subtitle_codec_c.as_ref().map_or(std::ptr::null(), |x| x.as_ptr())
    } else {
        std::ptr::null()
    };

    let mut ok = unsafe {
        aff_set_input_output(job, input.as_ptr(), output.as_ptr(), if request.overwrite { 1 } else { 0 }) == 0
    };
    if ok {
        ok = unsafe { aff_set_media_edit_inputs(job, additional_audio_ptr, subtitle_input_ptr, subtitle_codec_ptr) == 0 };
    }

    if ok {
        ok = unsafe { aff_clear_chapters(job) == 0 };
    }

    if ok {
        for (k, v) in request.metadata.iter() {
            let key_c = cstring(k)?;
            let value_c = cstring(v)?;
            ok = unsafe { aff_add_metadata(job, key_c.as_ptr(), value_c.as_ptr()) == 0 };
            if !ok {
                break;
            }
        }
    }

    if ok {
        for chapter in request.chapters.iter() {
            let title = cstring(&chapter.title)?;
            ok = unsafe { aff_add_chapter(job, chapter.start_ms, chapter.end_ms, title.as_ptr()) == 0 };
            if !ok {
                break;
            }
        }
    }

    if ok {
        ok = unsafe { aff_run_job_async(job, Some(log_callback), Some(progress_callback), std::ptr::null_mut()) == 0 };
    }

    let err = if ok { None } else { Some(last_error()) };
    unsafe { aff_destroy_job(job) };

    if let Some(err) = err {
        return Err(err);
    }
    Ok(())
}

pub fn run() {
    tauri::Builder::default()
        .manage(SharedState::new())
        .invoke_handler(tauri::generate_handler![
            create_tasks,
            list_tasks,
            start_queue,
            cancel_task,
            delete_task,
            clear_completed,
            set_concurrency,
            get_concurrency,
            pick_input_files,
            pick_image_files,
            pick_output_directory,
            render_image_preview,
            export_images_as_jpeg,
            reorder_tasks,
            detect_capabilities,
            run_media_edit
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
