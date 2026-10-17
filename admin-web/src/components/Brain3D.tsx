import { Html, OrbitControls } from '@react-three/drei'
import { Canvas, useFrame } from '@react-three/fiber'
import { useMemo, useRef, useState } from 'react'
import * as THREE from 'three'
import type { GraphEdge, GraphNode } from '../lib/api'

/** Детерминированный генератор (чтобы раскладка не «прыгала» между обновлениями). */
function rng(seed: number) {
  return () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
}

/** Силовая раскладка в 3D: отталкивание всех пар + пружины по связям + притяжение к центру. n ≤ ~500. */
export function layout3d(nodes: GraphNode[], edges: GraphEdge[], iterations = 220): Float32Array {
  const n = nodes.length
  const pos = new Float32Array(n * 3)
  const vel = new Float32Array(n * 3)
  const r = rng(42)
  for (let i = 0; i < n * 3; i++) pos[i] = (r() - 0.5) * 40
  const idx = new Map(nodes.map((nd, i) => [nd.id, i]))
  const E = edges.map((e) => [idx.get(e.a), idx.get(e.b)] as const).filter((e): e is readonly [number, number] => e[0] !== undefined && e[1] !== undefined && e[0] !== e[1])
  for (let it = 0; it < iterations; it++) {
    const cool = 1 - it / iterations
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        let dx = pos[i * 3] - pos[j * 3], dy = pos[i * 3 + 1] - pos[j * 3 + 1], dz = pos[i * 3 + 2] - pos[j * 3 + 2]
        const d2 = dx * dx + dy * dy + dz * dz + 0.05
        const f = (28 / d2) * cool
        dx *= f; dy *= f; dz *= f
        vel[i * 3] += dx; vel[i * 3 + 1] += dy; vel[i * 3 + 2] += dz
        vel[j * 3] -= dx; vel[j * 3 + 1] -= dy; vel[j * 3 + 2] -= dz
      }
    }
    for (const [a, b] of E) {
      const dx = pos[b * 3] - pos[a * 3], dy = pos[b * 3 + 1] - pos[a * 3 + 1], dz = pos[b * 3 + 2] - pos[a * 3 + 2]
      const d = Math.sqrt(dx * dx + dy * dy + dz * dz) + 0.01
      const f = (d - 5) * 0.04
      vel[a * 3] += (dx / d) * f; vel[a * 3 + 1] += (dy / d) * f; vel[a * 3 + 2] += (dz / d) * f
      vel[b * 3] -= (dx / d) * f; vel[b * 3 + 1] -= (dy / d) * f; vel[b * 3 + 2] -= (dz / d) * f
    }
    for (let i = 0; i < n; i++) {
      for (let k = 0; k < 3; k++) {
        vel[i * 3 + k] -= pos[i * 3 + k] * 0.012
        vel[i * 3 + k] *= 0.82
        pos[i * 3 + k] += vel[i * 3 + k]
      }
    }
  }
  return pos
}

const KIND_COLOR: Record<string, string> = { cluster: '--crater', road: '--muted', version: '--amber', feature: '--info', device: '--smooth' }
const css = (v: string) => getComputedStyle(document.documentElement).getPropertyValue(v).trim() || '#888'

function nodeColor(n: GraphNode): THREE.Color {
  if (n.kind === 'cluster') {
    if (n.status === 'fixed') return new THREE.Color(css('--smooth'))
    if (n.level === 'deep' || n.level === 'danger') return new THREE.Color(css('--crater'))
    return new THREE.Color(css('--warn'))
  }
  return new THREE.Color(css(KIND_COLOR[n.kind] ?? '--muted'))
}

function Scene({ nodes, edges, onSelect, selectedId, spin }: { nodes: GraphNode[]; edges: GraphEdge[]; onSelect: (n: GraphNode) => void; selectedId: string | null; spin: boolean }) {
  const pos = useMemo(() => layout3d(nodes, edges), [nodes, edges])
  const group = useRef<THREE.Group>(null)
  const [hover, setHover] = useState<number | null>(null)
  const lines = useMemo(() => {
    const idx = new Map(nodes.map((nd, i) => [nd.id, i]))
    const pts: number[] = []
    for (const e of edges) {
      const a = idx.get(e.a), b = idx.get(e.b)
      if (a === undefined || b === undefined || a === b) continue
      pts.push(pos[a * 3], pos[a * 3 + 1], pos[a * 3 + 2], pos[b * 3], pos[b * 3 + 1], pos[b * 3 + 2])
    }
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3))
    return g
  }, [nodes, edges, pos])
  useFrame((_, dt) => { if (spin && group.current) group.current.rotation.y += dt * 0.08 })
  const lineColor = useMemo(() => new THREE.Color(css('--line')), [])
  return (
    <group ref={group}>
      <lineSegments geometry={lines}><lineBasicMaterial color={lineColor} transparent opacity={0.55} /></lineSegments>
      {nodes.map((n, i) => {
        const radius = n.kind === 'version' ? 1.3 : 0.35 + Math.log2(1 + n.size) * 0.22
        const sel = n.id === selectedId
        return (
          <mesh key={n.id} position={[pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]]} scale={sel || hover === i ? 1.5 : 1}
            onClick={(e) => { e.stopPropagation(); onSelect(n) }} onPointerOver={(e) => { e.stopPropagation(); setHover(i) }} onPointerOut={() => setHover(null)}>
            <sphereGeometry args={[radius, 20, 20]} />
            <meshStandardMaterial color={nodeColor(n)} transparent opacity={0.35 + 0.65 * Math.max(0.15, Math.min(1, n.confidence))} emissive={nodeColor(n)} emissiveIntensity={sel ? 0.9 : 0.25} />
            {hover === i && <Html center distanceFactor={14} style={{ pointerEvents: 'none' }}><div className="whitespace-nowrap rounded-lg border border-line bg-surface px-2.5 py-1 text-xs">{n.label}</div></Html>}
          </mesh>
        )
      })}
    </group>
  )
}

/** 3D-визуализация «Мозга»: вращение мышью, приближение колесом, клик по узлу. Без WebGL показывает подсказку. */
export default function Brain3D({ nodes, edges, onSelect, selectedId }: { nodes: GraphNode[]; edges: GraphEdge[]; onSelect: (n: GraphNode) => void; selectedId: string | null }) {
  const reduce = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  return (
    <div className="h-full w-full" role="img" aria-label="3D-граф: узлы — ямы, дороги, версии, признаки, устройства">
      <Canvas camera={{ position: [0, 6, 34], fov: 55 }} dpr={[1, 2]} onPointerMissed={() => undefined}>
        <ambientLight intensity={0.8} />
        <pointLight position={[20, 25, 20]} intensity={90} />
        <Scene nodes={nodes} edges={edges} onSelect={onSelect} selectedId={selectedId} spin={!reduce} />
        <OrbitControls enableDamping makeDefault />
      </Canvas>
    </div>
  )
}
