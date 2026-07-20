import React from 'react';
import {
  AbsoluteFill,
  Audio,
  Img,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

export const DEMO_FPS = 30;
export const DEMO_DURATION = 900; // 30s

// Set true after dropping an ElevenLabs render at video/public/voiceover.mp3
const WITH_VOICEOVER = false;

// ---- Brand tokens (mirror site/styles.css + app Theme) ---------------------
const INK0 = '#07090B';
const INK1 = '#101214';
const MINT = '#2BDEB1';
const MINT_TEXT = '#B0F9E2';
const TEXT = '#F0F2F2';
const TEXT2 = 'rgba(255,255,255,0.62)';
const TEXT3 = 'rgba(255,255,255,0.52)';
const HAIRLINE = 'rgba(255,255,255,0.12)';
const SANS =
  '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, sans-serif';
const MONO =
  'ui-monospace, "SF Mono", Menlo, Monaco, "Cascadia Code", monospace';

const TAGLISH_1 = 'Na-approve na ba yung leave request ko?';
const TAGLISH_2 = "Send mo na lang sa akin yung report bago mag-launch.";

const smooth = { damping: 200 };
const snappy = { damping: 20, stiffness: 200 };

// Deterministic pseudo-noise, normalized to 0..1 (Remotion forbids Math.random()).
const wob = (frame: number, i: number) => {
  const raw =
    0.5 + 0.28 * Math.sin(frame / 3.1 + i * 1.7) + 0.22 * Math.sin(frame / 7.7 + i * 4.3);
  return Math.min(1, Math.max(0, raw));
};
// Bars must never collapse to a circle: BAR_W is the width, so the floor has to
// stay comfortably above it or a 12px-tall bar renders as a dot.
const BAR_W = 13;
const BAR_MIN = 30;

// A slow camera push. Sparse 1920x1080 compositions read as static; drifting
// ~5% across a scene fills the frame over time and keeps the eye moving without
// ever announcing itself. Applied per-Sequence, so `frame` here starts at 0.
const PushIn: React.FC<{
  children: React.ReactNode;
  duration: number;
  to?: number;
}> = ({ children, duration, to = 1.06 }) => {
  const frame = useCurrentFrame();
  const scale = interpolate(frame, [0, duration], [1, to], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  return <AbsoluteFill style={{ transform: `scale(${scale})` }}>{children}</AbsoluteFill>;
};

// ---- Shared bits -----------------------------------------------------------
const Bg: React.FC<{ glow?: number }> = ({ glow = 0.07 }) => (
  <AbsoluteFill
    style={{
      background: `radial-gradient(120% 90% at 50% 8%, rgba(43,222,177,${glow}) 0%, transparent 55%), ${INK0}`,
    }}
  />
);

const Caption: React.FC<{ children: React.ReactNode; delay?: number }> = ({
  children,
  delay = 0,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame, fps, delay, config: smooth, durationInFrames: 24 });
  return (
    <div
      style={{
        position: 'absolute',
        bottom: 130,
        width: '100%',
        textAlign: 'center',
        fontFamily: SANS,
        fontSize: 44,
        fontWeight: 500,
        letterSpacing: -0.4,
        color: TEXT2,
        opacity: p,
        transform: `translateY(${(1 - p) * 24}px)`,
      }}
    >
      {children}
    </div>
  );
};

// ---- The HUD pill, rebuilt for video (larger, cinematic) -------------------
const Hud: React.FC<{
  title: string;
  partial: string;
  done?: boolean;
}> = ({ title, partial, done }) => {
  const frame = useCurrentFrame();
  const bars = [0.35, 0.6, 1.0, 0.75, 0.5, 0.8, 0.4];
  const active = !done;
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 34,
        width: 1180,
        height: 220,
        padding: '0 52px',
        borderRadius: 60,
        background: `linear-gradient(135deg, #14181B 0%, #0B0E10 100%)`,
        border: `1.5px solid ${HAIRLINE}`,
        boxShadow: '0 60px 140px rgba(0,0,0,0.6)',
      }}
    >
      {/* orb / done badge */}
      <div style={{ width: 104, height: 104, position: 'relative', flexShrink: 0 }}>
        {done ? (
          <div
            style={{
              position: 'absolute',
              inset: 8,
              borderRadius: '50%',
              background: `radial-gradient(circle at 36% 30%, rgba(255,255,255,0.92), ${MINT} 55%, rgba(43,222,177,0.5))`,
              boxShadow: `0 0 60px rgba(43,222,177,0.5)`,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 46,
              fontWeight: 800,
              color: 'rgba(0,0,0,0.72)',
            }}
          >
            ✓
          </div>
        ) : (
          <>
            <div
              style={{
                position: 'absolute',
                inset: 0,
                borderRadius: '50%',
                background: `radial-gradient(circle, rgba(43,222,177,${
                  0.28 + 0.14 * Math.sin(frame / 6)
                }) 0%, transparent 65%)`,
              }}
            />
            <div
              style={{
                position: 'absolute',
                inset: 22,
                borderRadius: '50%',
                background: `radial-gradient(circle at 38% 33%, rgba(255,255,255,0.9), ${MINT} 58%, rgba(43,222,177,0.28))`,
                transform: `scale(${1 + 0.05 * Math.sin(frame / 5)})`,
                boxShadow: `0 6px 30px rgba(43,222,177,0.45)`,
              }}
            />
            <div
              style={{
                position: 'absolute',
                left: 34,
                top: 32,
                width: 10,
                height: 10,
                borderRadius: '50%',
                background: 'rgba(255,255,255,0.9)',
                filter: 'blur(0.5px)',
              }}
            />
          </>
        )}
      </div>

      {/* title + partial */}
      <div style={{ flexGrow: 1, minWidth: 0 }}>
        <div
          style={{
            fontFamily: SANS,
            fontSize: 42,
            fontWeight: 600,
            color: TEXT,
            letterSpacing: -0.3,
          }}
        >
          {title}
        </div>
        <div
          style={{
            fontFamily: MONO,
            fontSize: 30,
            color: done ? MINT_TEXT : TEXT2,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'clip',
            marginTop: 10,
          }}
        >
          {partial}
          {!done && partial.length > 0 ? (
            <span style={{ opacity: Math.sin(frame / 4) > 0 ? 1 : 0 }}>▎</span>
          ) : null}
        </div>
      </div>

      {/* waveform */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexShrink: 0 }}>
        {bars.map((cap, i) => (
          <div
            key={i}
            style={{
              width: BAR_W,
              borderRadius: BAR_W / 2,
              height: active
                ? BAR_MIN + cap * 74 * (0.35 + 0.65 * wob(frame, i))
                : BAR_MIN + cap * 16,
              background: i >= 2 && i <= 4 ? MINT : 'rgba(255,255,255,0.28)',
            }}
          />
        ))}
      </div>

      {/* badges */}
      <div style={{ display: 'flex', gap: 14, flexShrink: 0 }}>
        {['ON-DEVICE', 'TL'].map((b) => (
          <div
            key={b}
            style={{
              fontFamily: MONO,
              fontSize: 21,
              fontWeight: 700,
              color: TEXT3,
              padding: '10px 20px',
              borderRadius: 999,
              border: `1.5px solid ${HAIRLINE}`,
            }}
          >
            {b}
          </div>
        ))}
      </div>
    </div>
  );
};

// ---- Scene 1: logo intro ---------------------------------------------------
const Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame, fps, config: snappy, durationInFrames: 34 });
  const text = spring({ frame, fps, delay: 14, config: smooth, durationInFrames: 26 });
  const tag = spring({ frame, fps, delay: 30, config: smooth, durationInFrames: 26 });
  return (
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center' }}>
      <Bg glow={0.1} />
      <Img
        src={staticFile('logo3d.png')}
        style={{
          width: 620,
          height: 620,
          marginBottom: -90,
          transform: `scale(${pop}) rotate(${(1 - pop) * -14}deg)`,
          filter:
            'drop-shadow(0 30px 70px rgba(43,222,177,0.35)) saturate(1.25) contrast(1.1)',
        }}
      />
      <div
        style={{
          fontFamily: MONO,
          fontSize: 92,
          fontWeight: 600,
          letterSpacing: -2,
          color: TEXT,
          marginTop: 0,
          opacity: text,
          transform: `translateY(${(1 - text) * 30}px)`,
        }}
      >
        bulong
      </div>
      <div
        style={{
          fontFamily: SANS,
          fontSize: 46,
          color: TEXT2,
          marginTop: 22,
          opacity: tag,
          transform: `translateY(${(1 - tag) * 24}px)`,
        }}
      >
        Dictation that speaks <span style={{ color: MINT }}>Filipino</span>.
      </div>
    </AbsoluteFill>
  );
};

// ---- Scene 2: listening → transcribing → done ------------------------------
const HudScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: smooth, durationInFrames: 26 });

  // beats (local frames): 0–20 appear · 20–150 listening/typing ·
  // 150–195 transcribing · 195+ done
  const TYPE_START = 22;
  const TYPE_END = 148;
  const TRANSCRIBE = 152;
  const DONE = 196;

  const chars = Math.floor(
    interpolate(frame, [TYPE_START, TYPE_END], [0, TAGLISH_1.length], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
      easing: (t) => t,
    }),
  );
  const shown = TAGLISH_1.slice(0, chars);
  const phase = frame < TRANSCRIBE ? 'listen' : frame < DONE ? 'transcribe' : 'done';

  return (
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center' }}>
      <Bg />
      <div
        style={{
          opacity: enter,
          transform: `translateY(${(1 - enter) * 60}px) scale(${0.96 + enter * 0.04})`,
        }}
      >
        <Hud
          title={
            phase === 'listen'
              ? 'Listening'
              : phase === 'transcribe'
                ? 'Transcribing'
                : 'Done'
          }
          partial={
            phase === 'listen'
              ? `…${shown.slice(-38)}`
              : phase === 'transcribe'
                ? 'Working on-device…'
                : 'Inserted.'
          }
          done={phase === 'done'}
        />
      </div>
      <Caption key={phase} delay={phase === 'listen' ? 8 : 0}>
        {phase === 'listen'
          ? 'Press one key. Speak the way you actually speak.'
          : phase === 'transcribe'
            ? 'Transcribed on your Mac — nothing leaves the device.'
            : 'Done — and already in your app.'}
      </Caption>
    </AbsoluteFill>
  );
};

// ---- Scene 3: text lands in the app ---------------------------------------
const InsertScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: smooth, durationInFrames: 24 });
  const chars = Math.floor(
    interpolate(frame, [6, 66], [0, TAGLISH_1.length], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
    }),
  );
  return (
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center' }}>
      <Bg />
      {/* chat compose mock */}
      <div
        style={{
          width: 1240,
          borderRadius: 28,
          background: INK1,
          border: `1.5px solid ${HAIRLINE}`,
          boxShadow: '0 60px 140px rgba(0,0,0,0.55)',
          overflow: 'hidden',
          opacity: enter,
          transform: `translateY(${(1 - enter) * 60}px)`,
        }}
      >
        <div
          style={{
            height: 78,
            display: 'flex',
            alignItems: 'center',
            gap: 12,
            padding: '0 30px',
            borderBottom: `1px solid ${HAIRLINE}`,
          }}
        >
          {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => (
            <div key={c} style={{ width: 20, height: 20, borderRadius: '50%', background: c }} />
          ))}
          <div style={{ fontFamily: SANS, fontSize: 26, color: TEXT3, marginLeft: 16 }}>
            Any app — chat, editor, browser
          </div>
        </div>
        <div style={{ padding: 44 }}>
          <div
            style={{
              minHeight: 120,
              borderRadius: 18,
              border: `1.5px solid ${HAIRLINE}`,
              background: '#0B0E10',
              padding: '30px 34px',
              fontFamily: SANS,
              fontSize: 40,
              color: TEXT,
              lineHeight: 1.4,
            }}
          >
            {TAGLISH_1.slice(0, chars)}
            <span
              style={{
                opacity: Math.sin(frame / 4) > 0 ? 1 : 0,
                color: MINT,
              }}
            >
              ▎
            </span>
          </div>
        </div>
      </div>
      <Caption delay={10}>It types itself right where you're working.</Caption>
    </AbsoluteFill>
  );
};

// ---- Scene 4: feature chips -------------------------------------------------
const FEATURES = [
  '100% on-device',
  'No cloud. No account.',
  'English · Tagalog · Taglish',
  'One key. Talk.',
];

const FeatureScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center' }}>
      <Bg glow={0.09} />
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          gap: 34,
          alignItems: 'center',
        }}
      >
        {FEATURES.map((f, i) => {
          const p = spring({
            frame,
            fps,
            delay: 6 + i * 13,
            config: snappy,
            durationInFrames: 30,
          });
          return (
            <div
              key={f}
              style={{
                fontFamily: SANS,
                fontSize: 64,
                fontWeight: 600,
                letterSpacing: -1,
                color: i === 0 ? MINT_TEXT : TEXT,
                padding: '26px 64px',
                borderRadius: 999,
                border: `1.5px solid ${i === 0 ? 'rgba(43,222,177,0.5)' : HAIRLINE}`,
                background: i === 0 ? 'rgba(43,222,177,0.08)' : INK1,
                opacity: p,
                transform: `translateY(${(1 - p) * 46}px) scale(${0.9 + p * 0.1})`,
              }}
            >
              {f}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// ---- Scene 5: outro ---------------------------------------------------------
const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame, fps, config: smooth, durationInFrames: 32 });
  const t1 = spring({ frame, fps, delay: 16, config: smooth, durationInFrames: 26 });
  const t2 = spring({ frame, fps, delay: 30, config: smooth, durationInFrames: 26 });
  return (
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center' }}>
      <Bg glow={0.12} />
      <Img
        src={staticFile('icon3d.png')}
        style={{
          width: 360,
          height: 360,
          transform: `scale(${pop})`,
          filter:
            'drop-shadow(0 26px 50px rgba(0,0,0,0.55)) saturate(1.2) contrast(1.12)',
        }}
      />
      <div
        style={{
          fontFamily: MONO,
          fontSize: 76,
          fontWeight: 600,
          color: TEXT,
          marginTop: 30,
          opacity: t1,
          transform: `translateY(${(1 - t1) * 26}px)`,
        }}
      >
        bulong.app
      </div>
      <div
        style={{
          fontFamily: SANS,
          fontSize: 40,
          color: TEXT2,
          marginTop: 20,
          opacity: t2,
          transform: `translateY(${(1 - t2) * 22}px)`,
        }}
      >
        $29 once · free 14-day trial · Apple Silicon, macOS 14+
      </div>
    </AbsoluteFill>
  );
};

// ---- Timeline ---------------------------------------------------------------
export const BulongDemo: React.FC = () => {
  const { fps } = useVideoConfig();
  return (
    <AbsoluteFill style={{ background: INK0 }}>
      {WITH_VOICEOVER ? <Audio src={staticFile('voiceover.mp3')} /> : null}
      <Sequence durationInFrames={90} premountFor={30}>
        <PushIn duration={90} to={1.05}>
          <Intro />
        </PushIn>
      </Sequence>
      <Sequence from={90} durationInFrames={250} premountFor={1 * fps}>
        <PushIn duration={250} to={1.07}>
          <HudScene />
        </PushIn>
      </Sequence>
      <Sequence from={340} durationInFrames={170} premountFor={1 * fps}>
        <PushIn duration={170} to={1.05}>
          <InsertScene />
        </PushIn>
      </Sequence>
      <Sequence from={510} durationInFrames={170} premountFor={1 * fps}>
        <PushIn duration={170} to={1.05}>
          <FeatureScene />
        </PushIn>
      </Sequence>
      <Sequence from={680} durationInFrames={220} premountFor={1 * fps}>
        <PushIn duration={220} to={1.05}>
          <Outro />
        </PushIn>
      </Sequence>
    </AbsoluteFill>
  );
};
