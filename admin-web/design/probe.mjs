import fs from 'node:fs'
const env = Object.fromEntries(fs.readFileSync('../../backend/.env', 'utf8').split(/\r?\n/).filter((l) => l.includes('=')).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]))
export default async function run(page) {
  const logs = []
  page.on('console', (m) => logs.push(m.type() + ': ' + m.text().slice(0, 200)))
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.getByLabel('Логин').fill(env.ADMIN_USER)
  await page.getByLabel('Пароль').fill(env.ADMIN_PASSWORD)
  await page.getByRole('button', { name: 'Войти' }).click()
  await page.getByRole('heading', { name: 'Обзор' }).waitFor()
  await page.getByRole('link', { name: 'Карта', exact: true }).click()
  await page.waitForTimeout(4000)
  const dbg = await page.evaluate(() => ({ url: location.href, canvases: document.querySelectorAll('canvas').length, app: !!document.querySelector('[role=application]'), text: document.body.innerText.slice(0, 300) }))
  const info = await page.evaluate(() => { const e = document.querySelector('[role=application]'); return { ...e.dataset, w: e.clientWidth, h: e.clientHeight } })
  await page.screenshot({ path: 'shots/probe-map.png' })
  return { dbg, info, logs: logs.slice(0, 10) }
}
