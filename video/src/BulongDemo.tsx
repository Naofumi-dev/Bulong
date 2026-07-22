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
import { loadFont } from '@remotion/google-fonts/Nunito';

const { fontFamily: NUNITO } = loadFont('normal', {
  weights: ['700', '800'],
  subsets: ['latin'],
});

export const DEMO_FPS = 30;
export const DEMO_DURATION = 900; // 30s

// Set true after dropping an ElevenLabs render at video/public/voiceover.mp3
const WITH_VOICEOVER = false;

// ---- Brand tokens (light glass system — mirror site/styles.css) ------------
const PAPER = '#F3F7FA';
const CARD = '#FFFFFF';
const NAVY = '#13324B';
const NAVY2 = '#3E5E77';
const NAVY3 = '#6C879B';
const TEAL = '#178F7C';
const GRAD_A = '#3FC3AC';
const GRAD_B = '#4394D8';
const HAIRLINE = 'rgba(18,58,87,0.14)';
const GRAD = `linear-gradient(120deg, ${GRAD_A} 0%, ${GRAD_B} 100%)`;
const SANS =
  '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, sans-serif';
const MONO =
  'ui-monospace, "SF Mono", Menlo, Monaco, "Cascadia Code", monospace';

const TAGLISH_1 = 'Na-approve na ba yung leave request ko?';

const smooth = { damping: 200 };
const snappy = { damping: 20, stiffness: 200 };

// Deterministic pseudo-noise, normalized to 0..1 (Remotion forbids Math.random()).
const wob = (frame: number, i: number) => {
  const raw =
    0.5 + 0.28 * Math.sin(frame / 3.1 + i * 1.7) + 0.22 * Math.sin(frame / 7.7 + i * 4.3);
  return Math.min(1, Math.max(0, raw));
};
// Bars must never collapse to a circle: BAR_W is the width, so the floor has to
// stay comfortably above it or a short bar renders as a dot.
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
// Light aurora paper, matching the site's page background.
const Bg: React.FC<{ glow?: number }> = ({ glow = 0.12 }) => (
  <AbsoluteFill
    style={{
      background: `radial-gradient(90% 55% at 50% 0%, rgba(67,148,216,${glow}) 0%, rgba(63,195,172,${glow / 2}) 45%, transparent 72%), ${PAPER}`,
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
        color: NAVY2,
        opacity: p,
        transform: `translateY(${(1 - p) * 24}px)`,
      }}
    >
      {children}
    </div>
  );
};

// ---- The HUD pill: white glass, whisper mark, gradient bars ----------------
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
        background: `linear-gradient(175deg, #FFFFFF 0%, #EDF5F9 78%, #E2EEF5 100%)`,
        border: `1.5px solid rgba(18,58,87,0.16)`,
        boxShadow:
          '0 60px 140px -40px rgba(18,58,87,0.45), inset 0 2px 0 #fff',
      }}
    >
      {/* whisper mark / done badge */}
      <div
        style={{
          width: 110,
          height: 110,
          position: 'relative',
          flexShrink: 0,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {done ? (
          <div
            style={{
              width: 92,
              height: 92,
              borderRadius: '50%',
              background: GRAD,
              boxShadow: `0 14px 34px -10px rgba(56,140,190,0.65), inset 0 2px 0 rgba(255,255,255,0.5)`,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 46,
              fontWeight: 800,
              color: '#fff',
            }}
          >
            ✓
          </div>
        ) : (
          <Img
            src={staticFile('brand-mark.png')}
            style={{
              width: 104,
              height: 'auto',
              transform: `scale(${1 + 0.03 * Math.sin(frame / 6)})`,
              filter: 'drop-shadow(0 8px 18px rgba(18,58,87,0.35))',
            }}
          />
        )}
      </div>

      {/* title + partial */}
      <div style={{ flexGrow: 1, minWidth: 0 }}>
        <div
          style={{
            fontFamily: NUNITO,
            fontSize: 44,
            fontWeight: 800,
            color: NAVY,
            letterSpacing: -0.3,
          }}
        >
          {title}
        </div>
        <div
          style={{
            fontFamily: MONO,
            fontSize: 30,
            color: done ? TEAL : NAVY3,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'clip',
            marginTop: 10,
          }}
        >
          {partial}
          {!done && partial.length > 0 ? (
            <span style={{ opacity: Math.sin(frame / 4) > 0 ? 1 : 0, color: TEAL }}>▎</span>
          ) : null}
        </div>
      </div>

      {/* waveform: teal→blue gradient bars */}
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
              background:
                i >= 2 && i <= 4 ? GRAD : 'rgba(18,58,87,0.2)',
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
              color: NAVY2,
              padding: '10px 20px',
              borderRadius: 999,
              border: `1.5px solid ${HAIRLINE}`,
              background: CARD,
            }}
          >
            {b}
          </div>
        ))}
      </div>
    </div>
  );
};

// ---- Scene 1: whisper-mark intro -------------------------------------------
const Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame, fps, config: snappy, durationInFrames: 34 });
  const text = spring({ frame, fps, delay: 14, config: smooth, durationInFrames: 26 });
  const tag = spring({ frame, fps, delay: 30, config: smooth, durationInFrames: 26 });
  return (
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center' }}>
      <Bg glow={0.16} />
      <Img
        src={staticFile('brand-mark.png')}
        style={{
          width: 430,
          height: 'auto',
          transform: `scale(${pop}) rotate(${(1 - pop) * -10}deg)`,
          filter: 'drop-shadow(0 44px 80px rgba(18,58,87,0.35))',
        }}
      />
      <div
        style={{
          fontFamily: NUNITO,
          fontSize: 108,
          fontWeight: 800,
          letterSpacing: -2,
          color: NAVY,
          marginTop: 26,
          opacity: text,
          transform: `translateY(${(1 - text) * 30}px)`,
        }}
      >
        Bulong
      </div>
      <div
        style={{
          fontFamily: SANS,
          fontSize: 46,
          color: NAVY2,
          marginTop: 16,
          opacity: tag,
          transform: `translateY(${(1 - tag) * 24}px)`,
        }}
      >
        Dictation that speaks <span style={{ color: TEAL, fontWeight: 600 }}>Filipino</span>.
      </div>
    </AbsoluteFill>
  );
};

// ---- Scene 2: listening → transcribing → done ------------------------------
const HudScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: smooth, durationInFrames: 26 });

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

// ---- Scene 3: text lands in the app ----------------------------------------
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
      {/* light chat compose mock */}
      <div
        style={{
          width: 1240,
          borderRadius: 28,
          background: CARD,
          border: `1.5px solid ${HAIRLINE}`,
          boxShadow: '0 60px 140px -40px rgba(18,58,87,0.4), inset 0 1px 0 #fff',
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
            background: '#F6FAFC',
          }}
        >
          {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => (
            <div key={c} style={{ width: 20, height: 20, borderRadius: '50%', background: c }} />
          ))}
          <div style={{ fontFamily: SANS, fontSize: 26, color: NAVY3, marginLeft: 16 }}>
            Any app — chat, editor, browser
          </div>
        </div>
        <div style={{ padding: 44 }}>
          <div
            style={{
              minHeight: 120,
              borderRadius: 18,
              border: `1.5px solid ${HAIRLINE}`,
              background: '#F4F8FB',
              padding: '30px 34px',
              fontFamily: SANS,
              fontSize: 40,
              color: NAVY,
              lineHeight: 1.4,
            }}
          >
            {TAGLISH_1.slice(0, chars)}
            <span
              style={{
                opacity: Math.sin(frame / 4) > 0 ? 1 : 0,
                color: TEAL,
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
      <Bg glow={0.14} />
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
          const lead = i === 0;
          return (
            <div
              key={f}
              style={{
                fontFamily: NUNITO,
                fontSize: 64,
                fontWeight: 800,
                letterSpacing: -1,
                color: lead ? '#FFFFFF' : NAVY,
                padding: '26px 64px',
                borderRadius: 999,
                border: lead ? 'none' : `1.5px solid ${HAIRLINE}`,
                background: lead ? GRAD : CARD,
                boxShadow: lead
                  ? '0 24px 54px -18px rgba(56,140,190,0.6), inset 0 2px 0 rgba(255,255,255,0.4)'
                  : '0 18px 40px -24px rgba(18,58,87,0.35), inset 0 1px 0 #fff',
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

// ---- Scene 5: outro — the dark icon tile pops on light ----------------------
const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame, fps, config: smooth, durationInFrames: 32 });
  const t1 = spring({ frame, fps, delay: 16, config: smooth, durationInFrames: 26 });
  const t2 = spring({ frame, fps, delay: 30, config: smooth, durationInFrames: 26 });
  return (
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center' }}>
      <Bg glow={0.16} />
      <Img
        src={staticFile('brand-tile.png')}
        style={{
          width: 300,
          height: 300,
          borderRadius: 66,
          transform: `scale(${pop})`,
          filter: 'drop-shadow(0 40px 70px rgba(18,58,87,0.45))',
        }}
      />
      <div
        style={{
          fontFamily: NUNITO,
          fontSize: 84,
          fontWeight: 800,
          color: NAVY,
          marginTop: 34,
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
          color: NAVY2,
          marginTop: 18,
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
    <AbsoluteFill style={{ background: PAPER }}>
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
