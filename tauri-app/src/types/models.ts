export type ConversionDomain = 'video' | 'audio';

export interface ConversionTaskDraft {
  domain: ConversionDomain;
  input: string;
  output: string;
  format: string;
  overwrite: boolean;
  args: string[];
}

export type TaskStatus = 'queued' | 'running' | 'success' | 'failed' | 'cancelled';

export interface TaskProgress {
  processed_frames: number;
  processed_time_seconds: number;
  estimated_ratio: number;
  bitrate_kbps: number;
  speed: number;
}

export interface QueueTask {
  id: string;
  domain: ConversionDomain;
  input: string;
  output: string;
  format: string;
  status: TaskStatus;
  error?: string;
  created_at: string;
  updated_at: string;
  progress: TaskProgress;
}

export interface MediaEditRequest {
  input: string;
  output: string;
  overwrite: boolean;
  metadata: Record<string, string>;
  chapters: Array<{ start_ms: number; end_ms: number; title: string }>;
  additional_audio_input?: string;
  subtitle_input?: string;
  subtitle_codec?: string;
}
