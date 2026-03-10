<template>
  <v-container fluid class="pa-6">
    <v-card rounded="xl" class="pa-5">
      <div class="d-flex align-center mb-4">
        <div class="text-h6">{{ domain === 'video' ? '视频格式转换' : '音频格式转换' }}</div>
        <v-spacer />
        <v-chip size="small" color="info" variant="tonal">{{ summaryText }}</v-chip>
      </div>

      <v-row>
        <v-col cols="12" lg="7">
          <v-textarea
            v-model="inputText"
            label="输入文件（每行一个绝对路径）"
            variant="outlined"
            rows="8"
            hint="支持一次添加多个源文件，每个源文件将生成一个任务。"
            persistent-hint
          />
        </v-col>
        <v-col cols="12" lg="5">
          <v-select v-model="format" :items="availableFormats" label="输出格式" variant="outlined" />
          <v-radio-group v-model="outputMode" inline class="mt-2">
            <v-radio label="输出到源文件目录" value="source" />
            <v-radio label="输出到指定目录" value="specified" />
          </v-radio-group>
          <v-text-field
            v-model="outputDir"
            :disabled="outputMode === 'source'"
            label="指定输出目录"
            variant="outlined"
            class="mt-2"
          />
          <v-row class="mt-2">
            <v-col cols="6"><v-switch v-model="overwrite" label="覆盖同名文件" inset /></v-col>
            <v-col cols="6"><v-switch v-model="keepMetadata" label="保留元数据" inset /></v-col>
          </v-row>
        </v-col>
      </v-row>

      <v-divider class="my-4" />

      <div class="text-subtitle-1 mb-2">已选输入文件 ({{ selectedInputs.length }})</div>
      <v-sheet border rounded="lg" class="pa-2 mb-4" min-height="72">
        <div v-if="!selectedInputs.length" class="text-medium-emphasis">尚未选择输入文件</div>
        <v-chip
          v-for="file in selectedInputs"
          :key="file"
          closable
          class="mr-2 mb-2"
          size="small"
          @click:close="removeInput(file)"
        >
          {{ file }}
        </v-chip>
      </v-sheet>

      <v-expansion-panels multiple variant="accordion">
        <v-expansion-panel title="基础参数">
          <v-expansion-panel-text>
            <v-row>
              <v-col cols="12" md="3">
                <v-select v-model="preset" :items="['high', 'balanced', 'small']" label="参数预设" variant="outlined" />
              </v-col>
              <v-col cols="12" md="3">
                <v-text-field v-model="threadCount" label="线程数 (留空=自动)" variant="outlined" />
              </v-col>
              <v-col cols="12" md="3">
                <v-text-field v-model="startTime" label="开始时间 (-ss)" variant="outlined" />
              </v-col>
              <v-col cols="12" md="3">
                <v-text-field v-model="duration" label="时长 (-t)" variant="outlined" />
              </v-col>
            </v-row>
          </v-expansion-panel-text>
        </v-expansion-panel>

        <v-expansion-panel v-if="domain === 'video'" title="视频参数">
          <v-expansion-panel-text>
            <v-switch v-model="copyVideoStream" label="视频流 Copy (-c:v copy)" inset />
            <v-alert v-if="copyVideoStream" type="info" variant="tonal" density="compact" class="mb-3">
              已开启视频流 Copy，重编码参数将自动忽略。
            </v-alert>
            <v-row v-if="!copyVideoStream">
              <v-col cols="12" md="2">
                <v-select v-model="videoEncoder" :items="videoEncoders" label="视频编码器" variant="outlined" />
              </v-col>
              <v-col cols="12" md="2">
                <v-select v-model="videoPreset" :items="videoPresets" label="编码预设" variant="outlined" />
              </v-col>
              <v-col cols="12" md="2">
                <v-select v-model="videoScalePreset" :items="videoScalePresets" label="分辨率" variant="outlined" />
              </v-col>
              <v-col cols="12" md="2">
                <v-select v-model="videoRateControl" :items="videoRateControls" label="码控模式" variant="outlined" />
              </v-col>
              <v-col cols="12" md="2">
                <v-text-field v-model="videoFrameRate" label="帧率 (-r)" variant="outlined" />
              </v-col>
              <v-col cols="12" md="2">
                <v-switch v-model="enableDeinterlace" label="去隔行" inset />
              </v-col>
            </v-row>
            <v-row v-if="!copyVideoStream">
              <v-col cols="12" md="2" v-if="videoRateControl === 'crf'">
                <v-text-field v-model="videoCRF" label="CRF" variant="outlined" />
              </v-col>
              <v-col cols="12" md="2" v-else>
                <v-text-field v-model="videoBitrateKbps" label="视频码率(kbps)" variant="outlined" />
              </v-col>
              <v-col cols="12" md="2"><v-text-field v-model="videoMaxBitrateKbps" label="最大码率(kbps)" variant="outlined" /></v-col>
              <v-col cols="12" md="2"><v-text-field v-model="videoBufferSizeKbps" label="缓冲(kbps)" variant="outlined" /></v-col>
              <v-col cols="12" md="2"><v-text-field v-model="videoGOP" label="GOP" variant="outlined" /></v-col>
              <v-col cols="12" md="2"><v-text-field v-model="videoPixelFormat" label="像素格式" variant="outlined" /></v-col>
            </v-row>
            <v-row v-if="!copyVideoStream">
              <v-col cols="12" md="2"><v-select v-model="videoRotate" :items="videoRotateOptions" label="旋转" variant="outlined" /></v-col>
              <v-col cols="12" md="2"><v-switch v-model="videoFlipHorizontal" label="水平翻转" inset /></v-col>
              <v-col cols="12" md="2"><v-switch v-model="videoFlipVertical" label="垂直翻转" inset /></v-col>
              <v-col cols="12" md="2"><v-text-field v-model="videoCropWidth" label="裁剪宽" variant="outlined" /></v-col>
              <v-col cols="12" md="2"><v-text-field v-model="videoCropHeight" label="裁剪高" variant="outlined" /></v-col>
              <v-col cols="12" md="1"><v-text-field v-model="videoCropX" label="X" variant="outlined" /></v-col>
              <v-col cols="12" md="1"><v-text-field v-model="videoCropY" label="Y" variant="outlined" /></v-col>
            </v-row>
          </v-expansion-panel-text>
        </v-expansion-panel>

        <v-expansion-panel title="音频参数">
          <v-expansion-panel-text>
            <v-switch v-model="copyAudioStream" label="音频流 Copy (-c:a copy)" inset />
            <v-alert v-if="copyAudioStream" type="info" variant="tonal" density="compact" class="mb-3">
              已开启音频流 Copy，重编码参数将自动忽略。
            </v-alert>
            <v-row v-if="!copyAudioStream">
              <v-col cols="12" md="2"><v-select v-model="audioCodec" :items="audioCodecs" label="音频编码器" variant="outlined" /></v-col>
              <v-col cols="12" md="2"><v-text-field v-model="audioBitrateKbps" label="音频码率(kbps)" variant="outlined" /></v-col>
              <v-col cols="12" md="2"><v-text-field v-model="audioSampleRate" label="采样率(Hz)" variant="outlined" /></v-col>
              <v-col cols="12" md="2"><v-text-field v-model="audioChannels" label="声道" variant="outlined" /></v-col>
              <v-col cols="12" md="2"><v-text-field v-model="audioVBRQuality" label="VBR质量(0-9)" variant="outlined" /></v-col>
              <v-col cols="12" md="2"><v-text-field v-model="audioVolumeDB" label="音量(dB)" variant="outlined" /></v-col>
            </v-row>
            <v-row v-if="!copyAudioStream">
              <v-col cols="12" md="3"><v-switch v-model="enableLoudnorm" label="响度标准化 loudnorm" inset /></v-col>
              <v-col cols="12" md="3" v-if="enableLoudnorm"><v-text-field v-model="loudnormIntegratedTarget" label="目标I(LUFS)" variant="outlined" /></v-col>
              <v-col cols="12" md="3" v-if="enableLoudnorm"><v-text-field v-model="loudnormLraTarget" label="目标LRA" variant="outlined" /></v-col>
              <v-col cols="12" md="3" v-if="enableLoudnorm"><v-text-field v-model="loudnormTruePeakTarget" label="目标TP(dB)" variant="outlined" /></v-col>
            </v-row>
          </v-expansion-panel-text>
        </v-expansion-panel>

        <v-expansion-panel title="专家参数">
          <v-expansion-panel-text>
            <v-row>
              <v-col cols="12" md="2"><v-text-field v-model="selectedAudioTrackIndex" label="音轨索引" variant="outlined" /></v-col>
              <v-col cols="12" md="10"><v-textarea v-model="customFFmpegArgs" label="自定义参数（空格分隔）" variant="outlined" rows="3" /></v-col>
            </v-row>
          </v-expansion-panel-text>
        </v-expansion-panel>
      </v-expansion-panels>

      <div class="d-flex justify-end mt-5">
        <v-btn color="primary" size="large" @click="submit">添加任务</v-btn>
      </div>
    </v-card>
  </v-container>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useQueueStore } from '@/stores/queue';
import type { ConversionDomain, ConversionTaskDraft } from '@/types/models';

const props = defineProps<{ domain: ConversionDomain }>();
const queue = useQueueStore();
const router = useRouter();

const inputText = ref('');
const outputMode = ref<'source' | 'specified'>('source');
const outputDir = ref('/Users/albert/Documents/FFOutput');
const format = ref(props.domain === 'video' ? 'mp4' : 'm4a');
const overwrite = ref(true);
const keepMetadata = ref(true);
const preset = ref<'high' | 'balanced' | 'small'>('balanced');
const threadCount = ref('');
const startTime = ref('');
const duration = ref('');
const selectedAudioTrackIndex = ref('');
const customFFmpegArgs = ref('');

const copyVideoStream = ref(false);
const videoEncoder = ref<'auto' | 'h264' | 'h265' | 'av1'>('auto');
const videoPreset = ref('medium');
const videoScalePreset = ref<'source' | '2160' | '1440' | '1080' | '720' | '480'>('source');
const videoRateControl = ref<'crf' | 'bitrate'>('crf');
const videoCRF = ref('23');
const videoBitrateKbps = ref('2500');
const videoFrameRate = ref('');
const videoMaxBitrateKbps = ref('');
const videoBufferSizeKbps = ref('');
const videoGOP = ref('');
const videoPixelFormat = ref('');
const enableDeinterlace = ref(false);
const videoRotate = ref<'none' | 'cw90' | 'ccw90' | 'r180'>('none');
const videoFlipHorizontal = ref(false);
const videoFlipVertical = ref(false);
const videoCropWidth = ref('');
const videoCropHeight = ref('');
const videoCropX = ref('0');
const videoCropY = ref('0');

const copyAudioStream = ref(false);
const audioCodec = ref<'auto' | 'aac' | 'mp3' | 'opus' | 'vorbis' | 'flac' | 'alac' | 'pcm_s16le'>('auto');
const audioBitrateKbps = ref('192');
const audioSampleRate = ref('44100');
const audioChannels = ref('2');
const audioVBRQuality = ref('');
const audioVolumeDB = ref('');
const enableLoudnorm = ref(false);
const loudnormIntegratedTarget = ref('-16');
const loudnormLraTarget = ref('11');
const loudnormTruePeakTarget = ref('-1.5');

const videoFormats = ['mp4', 'mov', 'mkv', 'webm', 'avi', 'flv', 'm4v', 'ts', 'mpeg', 'ogv', '3gp', 'gif'];
const audioFormats = ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'opus', 'aiff', 'wma', 'alac'];
const videoEncoders = ['auto', 'h264', 'h265', 'av1'];
const audioCodecs = ['auto', 'aac', 'mp3', 'opus', 'vorbis', 'flac', 'alac', 'pcm_s16le'];
const videoPresets = ['none', 'ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow'];
const videoScalePresets = ['source', '2160', '1440', '1080', '720', '480'];
const videoRateControls = ['crf', 'bitrate'];
const videoRotateOptions = ['none', 'cw90', 'ccw90', 'r180'];

const selectedInputs = computed(() => inputText.value.split('\n').map((x) => x.trim()).filter(Boolean));
const availableFormats = computed(() => (props.domain === 'video' ? videoFormats : audioFormats));

const summaryText = computed(() => {
  const rows = [
    `预设=${preset.value}`,
    `输出=${outputMode.value === 'source' ? '源目录' : '指定目录'}`,
    `覆盖=${overwrite.value ? '是' : '否'}`
  ];
  if (props.domain === 'video') {
    rows.push(copyVideoStream.value ? '视频流=copy' : `编码=${videoEncoder.value}`);
  }
  rows.push(copyAudioStream.value ? '音频流=copy' : `音频编码=${audioCodec.value}`);
  return rows.join(' | ');
});

const removeInput = (file: string): void => {
  inputText.value = selectedInputs.value.filter((f) => f !== file).join('\n');
};

const baseName = (path: string): string => {
  const file = path.split('/').pop() || path;
  return file.replace(/\.[^.]+$/, '');
};

const parentDir = (path: string): string => {
  const idx = path.lastIndexOf('/');
  return idx > 0 ? path.slice(0, idx) : '.';
};

const codecArg = (): string[] => {
  if (audioCodec.value === 'auto') return [];
  const map: Record<string, string> = {
    aac: 'aac',
    mp3: 'libmp3lame',
    opus: 'libopus',
    vorbis: 'libvorbis',
    flac: 'flac',
    alac: 'alac',
    pcm_s16le: 'pcm_s16le'
  };
  return ['-c:a', map[audioCodec.value] ?? audioCodec.value];
};

const videoEncoderArg = (): string[] => {
  const map: Record<string, string> = { h264: 'libx264', h265: 'libx265', av1: 'libsvtav1' };
  const codec = map[videoEncoder.value];
  return codec ? ['-c:v', codec] : [];
};

const buildArgs = (): string[] => {
  const args: string[] = [];
  const vf: string[] = [];
  const af: string[] = [];

  if (selectedAudioTrackIndex.value.trim()) {
    if (props.domain === 'video') args.push('-map', '0:v?', '-map', `0:a:${selectedAudioTrackIndex.value.trim()}`, '-map', '0:s?');
    else args.push('-map', `0:a:${selectedAudioTrackIndex.value.trim()}`);
  }
  if (startTime.value.trim()) args.push('-ss', startTime.value.trim());
  if (duration.value.trim()) args.push('-t', duration.value.trim());
  if (threadCount.value.trim()) args.push('-threads', threadCount.value.trim());
  if (!keepMetadata.value) args.push('-map_metadata', '-1');

  if (props.domain === 'video') {
    if (copyVideoStream.value) {
      args.push('-c:v', 'copy');
    } else {
      args.push(...videoEncoderArg());
      if (videoPreset.value !== 'none') args.push('-preset', videoPreset.value);
      if (videoRateControl.value === 'crf') args.push('-crf', videoCRF.value || '23');
      else if (videoBitrateKbps.value.trim()) args.push('-b:v', `${videoBitrateKbps.value.trim()}k`);
      if (videoFrameRate.value.trim()) args.push('-r', videoFrameRate.value.trim());
      if (videoMaxBitrateKbps.value.trim()) args.push('-maxrate', `${videoMaxBitrateKbps.value.trim()}k`);
      if (videoBufferSizeKbps.value.trim()) args.push('-bufsize', `${videoBufferSizeKbps.value.trim()}k`);
      if (videoGOP.value.trim()) args.push('-g', videoGOP.value.trim());
      if (videoPixelFormat.value.trim()) args.push('-pix_fmt', videoPixelFormat.value.trim());
      if (enableDeinterlace.value) vf.push('yadif');
      if (videoScalePreset.value !== 'source') vf.push(`scale=-2:${videoScalePreset.value}`);
      if (videoRotate.value === 'cw90') vf.push('transpose=1');
      if (videoRotate.value === 'ccw90') vf.push('transpose=2');
      if (videoRotate.value === 'r180') vf.push('transpose=1,transpose=1');
      if (videoFlipHorizontal.value) vf.push('hflip');
      if (videoFlipVertical.value) vf.push('vflip');
      if (videoCropWidth.value.trim() && videoCropHeight.value.trim()) {
        vf.push(`crop=${videoCropWidth.value.trim()}:${videoCropHeight.value.trim()}:${videoCropX.value.trim() || '0'}:${videoCropY.value.trim() || '0'}`);
      }
    }
  }

  if (format.value !== 'gif') {
    if (copyAudioStream.value) {
      args.push('-c:a', 'copy');
    } else {
      args.push(...codecArg());
      if (audioBitrateKbps.value.trim()) args.push('-b:a', `${audioBitrateKbps.value.trim()}k`);
      if (audioSampleRate.value.trim()) args.push('-ar', audioSampleRate.value.trim());
      if (audioChannels.value.trim()) args.push('-ac', audioChannels.value.trim());
      if (audioVBRQuality.value.trim()) args.push('-q:a', audioVBRQuality.value.trim());
      if (audioVolumeDB.value.trim()) af.push(`volume=${audioVolumeDB.value.trim()}dB`);
      if (enableLoudnorm.value) {
        af.push(`loudnorm=I=${loudnormIntegratedTarget.value.trim() || '-16'}:LRA=${loudnormLraTarget.value.trim() || '11'}:TP=${loudnormTruePeakTarget.value.trim() || '-1.5'}`);
      }
    }
  }

  if (vf.length && !copyVideoStream.value) args.push('-vf', vf.join(','));
  if (af.length && !copyAudioStream.value) args.push('-af', af.join(','));
  if (customFFmpegArgs.value.trim()) args.push(...customFFmpegArgs.value.trim().split(/\s+/g));
  return args;
};

const outputForInput = (input: string): string => {
  const outDir = outputMode.value === 'source' ? parentDir(input) : outputDir.value.trim();
  return `${outDir.replace(/\/$/, '')}/${baseName(input)}.${format.value}`;
};

const applyPreset = (): void => {
  if (preset.value === 'high') {
    videoRateControl.value = 'crf';
    videoCRF.value = '18';
    videoPreset.value = 'slow';
    audioBitrateKbps.value = '320';
  } else if (preset.value === 'balanced') {
    videoRateControl.value = 'crf';
    videoCRF.value = '23';
    videoPreset.value = 'medium';
    audioBitrateKbps.value = '192';
  } else {
    videoRateControl.value = 'crf';
    videoCRF.value = '30';
    videoPreset.value = 'faster';
    audioBitrateKbps.value = '128';
  }
};

const submit = async (): Promise<void> => {
  applyPreset();
  const files = selectedInputs.value;
  if (!files.length) {
    queue.pushLog('请先输入至少一个文件路径');
    return;
  }
  if (outputMode.value === 'specified' && !outputDir.value.trim()) {
    queue.pushLog('请选择输出目录或切换为源文件目录输出');
    return;
  }
  const args = buildArgs();
  const drafts: ConversionTaskDraft[] = files.map((input) => ({
    domain: props.domain,
    input,
    output: outputForInput(input),
    format: format.value,
    overwrite: overwrite.value,
    args
  }));
  await queue.addTasks(drafts);
  inputText.value = '';
  await router.push('/tasks');
};
</script>
