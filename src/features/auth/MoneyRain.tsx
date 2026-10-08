import type { CSSProperties } from 'react'

import billPng from '@/assets/bill.png'
import coinPng from '@/assets/coin.png'

// Decorative money rain for the auth screens. Pure CSS animation — the
// wrapper falls (translateY), the sprite inside sways/rotates. All
// randomness is generated once at module load so sprites never teleport.
// Hidden entirely under prefers-reduced-motion (see index.css).
const COUNT = 28

const ITEMS = Array.from({ length: COUNT }, () => ({
  coin: Math.random() < 0.35,
  left: Math.random() * 100,
  size: 28 + Math.random() * 36,
  dur: 7 + Math.random() * 8,
  // Negative delay puts sprites mid-flight on first paint.
  delay: -Math.random() * 15,
  sway: 8 + Math.random() * 24,
  swayDur: 1.6 + Math.random() * 2.4,
  rot: 12 + Math.random() * 20,
  opacity: 0.35 + Math.random() * 0.4,
}))

export function MoneyRain() {
  return (
    <div
      aria-hidden
      className="money-rain-layer pointer-events-none absolute inset-0 overflow-hidden"
    >
      {ITEMS.map((it, i) => (
        <div
          key={i}
          className="absolute top-0"
          style={{
            left: `${it.left}%`,
            opacity: it.opacity,
            animation: `money-fall ${it.dur}s linear ${it.delay}s infinite`,
          }}
        >
          <img
            src={it.coin ? coinPng : billPng}
            alt=""
            style={
              {
                width: it.size,
                imageRendering: 'pixelated',
                '--sway': `${it.sway}px`,
                '--rot': `${it.rot}deg`,
                animation: `money-sway ${it.swayDur}s ease-in-out infinite`,
              } as CSSProperties
            }
          />
        </div>
      ))}
    </div>
  )
}
