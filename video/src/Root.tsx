import React from 'react';
import { Composition } from 'remotion';
import { BulongDemo, DEMO_DURATION, DEMO_FPS } from './BulongDemo';

export const Root: React.FC = () => (
  <Composition
    id="BulongDemo"
    component={BulongDemo}
    durationInFrames={DEMO_DURATION}
    fps={DEMO_FPS}
    width={1920}
    height={1080}
  />
);
