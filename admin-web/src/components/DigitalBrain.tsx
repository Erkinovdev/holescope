import { Html, OrbitControls } from '@react-three/drei'
import { Canvas, useFrame } from '@react-three/fiber'
import { useMemo, useRef, useState } from 'react'
import * as THREE from 'three'

/** Детерминированный генератор: мозг выглядит одинаково при каждой загрузке. */
function rng(seed: number) {
  return () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
}

export interface BrainRegion { key: string; name: string; sub: string; color: string; pos: [number, number, number] }
/** Области мозга = модели ИИ. Положение — на поверхности полушарий. */
export const REGIONS: BrainRegion[] = [
  { key: 'sezgi', name: 'Сезги', sub: 'ощущение', color: '#ffb020', pos: [-1.9, 1.3, 3.3] },
  { key: 'nazar', name: 'Назар', sub: 'взгляд', color: '#4da3ff', pos: [1.9, 1.3, 3.3] },
  { key: 'mezon', name: 'Мезон', sub: 'мерило', color: '#3ecf8e', pos: [-3.0, 0.2, 0.2] },
  { key: 'xotira', name: 'Хотира', sub: 'память', color: '#ff5d5d', pos: [3.0, 0.2, 0.2] },
  { key: 'ustoz', name: 'Устоз', sub: 'наставник', color: '#ffb020', pos: [0, 2.3, 0.4] },
  { key: 'holi', name: 'Холи', sub: 'голос', color: '#4da3ff', pos: [0, -1.9, -3.3] },
]

/** Извилины: сумма синусов разных частот — похоже на борозды коры. */
function gyri(x: number, y: number, z: number): number {
  return Math.sin(x * 3.1 + y * 2.3 + z * 1.7) * Math.sin(y * 3.7 - z * 2.9 + x * 1.3) + 0.7 * Math.sin(z * 5.3 + x * 3.9) * Math.sin(y * 5.9 + z * 2.1) + 0.4 * Math.sin((x + y + z) * 7.1)
}

/** Точка на коре: эллипсоид мозга (ширина × высота × длина), приплюснутое основание, межполушарная щель сверху. */
function cortexPoint(u: number, v: number): THREE.Vector3 {
  const th = Math.acos(1 - 2 * u), ph = 2 * Math.PI * v
  let x = Math.sin(th) * Math.cos(ph), y = Math.cos(th), z = Math.sin(th) * Math.sin(ph)
  const g = gyri(x * 2.2, y * 2.2, z * 2.2)
  const rad = 1 + 0.07 * g
  let px = 3.1 * x * rad, py = 2.3 * y * rad, pz = 4.2 * z * rad
  if (py < -0.5) py = -0.5 + (py + 0.5) * 0.55            // плоское основание
  const front = Math.max(0, pz / 4.2)
  px *= 1 - 0.18 * front * front                         // лобные доли уже затылочных
  if (py > 0) py -= 0.55 * Math.exp(-((px / 0.32) ** 2)) * Math.min(1, py / 1.2)  // продольная щель
  return new THREE.Vector3(px, py, pz)
}

/** Мозжечок: меньший эллипсоид сзади снизу с частыми бороздами; ствол мозга — короткий столбик вниз. */
function cerebellumPoint(u: number, v: number): THREE.Vector3 {
  const th = Math.acos(1 - 2 * u), ph = 2 * Math.PI * v
  const x = Math.sin(th) * Math.cos(ph), y = Math.cos(th), z = Math.sin(th) * Math.sin(ph)
  const ridges = 1 + 0.06 * Math.sin(y * 24 + z * 3)
  return new THREE.Vector3(1.55 * x * ridges, -1.95 + 0.85 * y * ridges, -2.7 + 1.15 * z * ridges)
}

function buildBrain() {
  const r = rng(7)
  const pts: THREE.Vector3[] = []
  for (let i = 0; i < 6200; i++) {
    const p = cortexPoint(r(), r())
    if (r() < 0.16) p.multiplyScalar(0.5 + r() * 0.42)      // объём под корой
    pts.push(p)
  }
  for (let i = 0; i < 1100; i++) pts.push(cerebellumPoint(r(), r()))
  for (let i = 0; i < 260; i++) { const a = r() * 6.283, h = r(); pts.push(new THREE.Vector3(Math.cos(a) * 0.32, -1.3 - h * 1.5, -1.1 - h * 0.5 + Math.sin(a) * 0.32)) }
  const pos = new Float32Array(pts.length * 3)
  const phase = new Float32Array(pts.length)
  const size = new Float32Array(pts.length)
  pts.forEach((p, i) => { pos.set([p.x, p.y, p.z], i * 3); phase[i] = r() * 6.283; size[i] = 0.6 + r() * 0.9 })
  // нейроны: яркие узлы по коре и связи между ближайшими
  const nodes: THREE.Vector3[] = []
  for (let i = 0; i < 170; i++) nodes.push(cortexPoint(r(), r()))
  const edges: [number, number][] = []
  nodes.forEach((a, i) => {
    const near = nodes.map((b, j) => ({ j, d: a.distanceTo(b) })).filter((o) => o.j !== i && o.d < 2.6).sort((p, q) => p.d - q.d).slice(0, 3)
    near.forEach((o) => { if (!edges.some(([x, y]) => (x === i && y === o.j) || (x === o.j && y === i))) edges.push([i, o.j]) })
  })
  return { pos, phase, size, nodes, edges, count: pts.length }
}

const VERT = /* glsl */ `
  attribute float aPhase; attribute float aSize;
  uniform float uTime; uniform float uActivity; uniform float uPixel;
  varying float vGlow; varying float vZ;
  void main(){
    vec4 mv = modelViewMatrix * vec4(position, 1.0);
    // волна обработки: яркий фронт бежит вдоль мозга спереди назад; скорость растёт с активностью
    float wave = 0.5 + 0.5 * sin(position.z * 1.1 - uTime * (0.9 + uActivity * 1.8));
    float twinkle = 0.5 + 0.5 * sin(uTime * 1.3 + aPhase * 3.0);
    vGlow = 0.25 + 0.55 * pow(wave, 6.0) * (0.5 + uActivity) + 0.2 * twinkle;
    vZ = position.z;
    gl_PointSize = aSize * uPixel * (1.0 + 1.6 * pow(wave, 6.0)) * (9.0 / -mv.z);
    gl_Position = projectionMatrix * mv;
  }`
const FRAG = /* glsl */ `
  uniform vec3 uBase; uniform vec3 uHot;
  varying float vGlow; varying float vZ;
  void main(){
    vec2 c = gl_PointCoord - 0.5; float d = length(c);
    if (d > 0.5) discard;
    float a = smoothstep(0.5, 0.0, d);
    vec3 col = mix(uBase, uHot, clamp(vGlow * 1.2 - 0.25, 0.0, 1.0));
    gl_FragColor = vec4(col * (0.5 + vGlow * 0.8), a * (0.34 + vGlow * 0.6));
  }`

function Brain({ activity, selected, onSelect, spin, hover, setHover }: {
  activity: number; selected: string | null; onSelect: (k: string) => void; spin: boolean; hover: string | null; setHover: (k: string | null) => void
}) {
  const data = useMemo(buildBrain, [])
  const group = useRef<THREE.Group>(null)
  const mat = useRef<THREE.ShaderMaterial>(null)
  const pulses = useRef<THREE.InstancedMesh>(null)
  const css = (v: string, fb: string) => (typeof document === 'undefined' ? fb : getComputedStyle(document.documentElement).getPropertyValue(v).trim() || fb)
  const uniforms = useMemo(() => ({
    uTime: { value: 0 }, uActivity: { value: 0.4 }, uPixel: { value: Math.min(window.devicePixelRatio || 1, 2) * 3.1 },
    uBase: { value: new THREE.Color(css('--amber', '#ffb020')).multiplyScalar(0.85) }, uHot: { value: new THREE.Color('#ffd98a') },
  }), []) // eslint-disable-line react-hooks/exhaustive-deps
  const lines = useMemo(() => {
    const p: number[] = []
    data.edges.forEach(([a, b]) => { const A = data.nodes[a], B = data.nodes[b]; p.push(A.x, A.y, A.z, B.x, B.y, B.z) })
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(p, 3)); return g
  }, [data])
  const N_PULSE = 90
  const pulseState = useMemo(() => Array.from({ length: N_PULSE }, (_, i) => ({ e: (i * 7) % Math.max(1, data.edges.length), t: (i * 0.137) % 1, sp: 0.25 + ((i * 53) % 17) / 40 })), [data])
  const dummy = useMemo(() => new THREE.Object3D(), [])
  const regionPos = useMemo(() => REGIONS.map((r) => {
    // ближайшая точка поверхности к желаемой позиции
    let best = 0, bd = 1e9
    for (let i = 0; i < data.count; i++) { const dx = data.pos[i * 3] - r.pos[0], dy = data.pos[i * 3 + 1] - r.pos[1], dz = data.pos[i * 3 + 2] - r.pos[2]; const d = dx * dx + dy * dy + dz * dz; if (d < bd) { bd = d; best = i } }
    return new THREE.Vector3(data.pos[best * 3], data.pos[best * 3 + 1], data.pos[best * 3 + 2])
  }), [data])

  useFrame((s, dt) => {
    const t = s.clock.elapsedTime
    if (mat.current) { mat.current.uniforms.uTime.value = t; mat.current.uniforms.uActivity.value += (activity - mat.current.uniforms.uActivity.value) * Math.min(1, dt * 2) }
    if (group.current && spin) group.current.rotation.y += dt * 0.12
    if (pulses.current) {
      pulseState.forEach((p, i) => {
        p.t += dt * p.sp * (0.5 + activity * 1.5)
        if (p.t >= 1) { p.t = 0; p.e = Math.floor(Math.random() * data.edges.length) }
        const [a, b] = data.edges[p.e] ?? [0, 0]
        const A = data.nodes[a], B = data.nodes[b]
        dummy.position.set(A.x + (B.x - A.x) * p.t, A.y + (B.y - A.y) * p.t, A.z + (B.z - A.z) * p.t)
        dummy.scale.setScalar(0.5 + Math.sin(p.t * Math.PI) * 0.9)
        dummy.updateMatrix(); pulses.current!.setMatrixAt(i, dummy.matrix)
      })
      pulses.current.instanceMatrix.needsUpdate = true
    }
  })
  return (
    <group ref={group} rotation={[0.1, 0.95, 0]}>
      <points frustumCulled={false}>
        <bufferGeometry>
          <bufferAttribute attach="attributes-position" args={[data.pos, 3]} />
          <bufferAttribute attach="attributes-aPhase" args={[data.phase, 1]} />
          <bufferAttribute attach="attributes-aSize" args={[data.size, 1]} />
        </bufferGeometry>
        <shaderMaterial ref={mat} vertexShader={VERT} fragmentShader={FRAG} uniforms={uniforms} transparent depthWrite={false} blending={THREE.AdditiveBlending} />
      </points>
      <lineSegments geometry={lines}><lineBasicMaterial color="#ffb020" transparent opacity={0.16} blending={THREE.AdditiveBlending} depthWrite={false} /></lineSegments>
      <instancedMesh ref={pulses} args={[undefined, undefined, N_PULSE]} frustumCulled={false}>
        <sphereGeometry args={[0.05, 8, 8]} />
        <meshBasicMaterial color="#fff1c7" transparent opacity={0.95} blending={THREE.AdditiveBlending} depthWrite={false} />
      </instancedMesh>
      {data.nodes.map((n, i) => <mesh key={i} position={n}><sphereGeometry args={[0.035, 8, 8]} /><meshBasicMaterial color="#ffd27a" transparent opacity={0.5} blending={THREE.AdditiveBlending} depthWrite={false} /></mesh>)}
      {REGIONS.map((r, i) => {
        const on = selected === r.key, hv = hover === r.key
        return (
          <group key={r.key} position={regionPos[i]}>
            <mesh onClick={(e) => { e.stopPropagation(); onSelect(r.key) }} onPointerOver={(e) => { e.stopPropagation(); setHover(r.key); document.body.style.cursor = 'pointer' }} onPointerOut={() => { setHover(null); document.body.style.cursor = '' }} scale={on || hv ? 1.5 : 1}>
              <sphereGeometry args={[0.19, 24, 24]} />
              <meshBasicMaterial color={r.color} transparent opacity={on ? 1 : 0.85} />
            </mesh>
            <mesh scale={on ? 3.4 : 2.2}><sphereGeometry args={[0.19, 20, 20]} /><meshBasicMaterial color={r.color} transparent opacity={on ? 0.28 : 0.14} blending={THREE.AdditiveBlending} depthWrite={false} /></mesh>
            <Html center distanceFactor={11} position={[0, 0.5, 0]} style={{ pointerEvents: 'none' }}>
              <div style={{ whiteSpace: 'nowrap', transform: 'translateY(-6px)', padding: '3px 10px', borderRadius: 999, background: 'color-mix(in srgb, var(--bg-surface) 82%, transparent)', border: `1px solid ${on ? r.color : 'var(--line)'}`, backdropFilter: 'blur(6px)', fontSize: 12, fontWeight: 700, color: 'var(--text)', boxShadow: on ? `0 0 18px ${r.color}66` : undefined }}>
                <span style={{ color: r.color }}>●</span> {r.name}
              </div>
            </Html>
          </group>
        )
      })}
      {/* кольца «обработки» вокруг мозга */}
      <Ring radius={5.9} speed={0.35} tilt={[1.25, 0, 0.2]} opacity={0.22} />
      <Ring radius={6.6} speed={-0.22} tilt={[1.0, 0.3, -0.4]} opacity={0.14} />
    </group>
  )
}

function Ring({ radius, speed, tilt, opacity }: { radius: number; speed: number; tilt: [number, number, number]; opacity: number }) {
  const ref = useRef<THREE.Mesh>(null)
  useFrame((_, dt) => { if (ref.current) ref.current.rotation.z += dt * speed })
  return (
    <mesh ref={ref} rotation={tilt}>
      <torusGeometry args={[radius, 0.012, 6, 160]} />
      <meshBasicMaterial color="#ffb020" transparent opacity={opacity} blending={THREE.AdditiveBlending} depthWrite={false} />
    </mesh>
  )
}

function hasWebGL() {
  try { const c = document.createElement('canvas'); return !!(c.getContext('webgl2') || c.getContext('webgl')) } catch { return false }
}

/** Цифровой мозг Holescope: полушария из тысяч светящихся точек, бегущая волна обработки данных, нейроны с импульсами.
 *  Шесть светящихся узлов — это модели ИИ (Сезги, Назар, Мезон, Хотира, Устоз, Холи); клик выбирает модель. */
export default function DigitalBrain({ activity = 0.4, selected, onSelect }: { activity?: number; selected: string | null; onSelect: (k: string) => void }) {
  const reduce = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  const [hover, setHover] = useState<string | null>(null)
  const ok = useMemo(hasWebGL, [])
  if (!ok) return <div className="grid h-full place-items-center text-sm text-muted">3D недоступно в этом браузере: включите аппаратное ускорение графики.</div>
  return (
    <div className="h-full w-full" role="img" aria-label="Цифровой мозг Holescope: шесть моделей ИИ как области мозга">
      <Canvas camera={{ position: [0, 1.6, 11.6], fov: 44 }} dpr={[1, 2]} gl={{ antialias: true, alpha: true }}>
        <Brain activity={activity} selected={selected} onSelect={onSelect} spin={!reduce && !hover} hover={hover} setHover={setHover} />
        <OrbitControls enablePan={false} enableDamping minDistance={8} maxDistance={20} autoRotate={false} />
      </Canvas>
    </div>
  )
}
