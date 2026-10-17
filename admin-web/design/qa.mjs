import fs from 'node:fs'
const env = Object.fromEntries(fs.readFileSync('../../backend/.env', 'utf8').split(/\r?\n/).filter((l) => l.includes('=')).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]))
export default async function run(page) {
  const out = { steps: [] }
  const errors = []
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 200)))
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)) })
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.getByLabel('Логин').fill(env.ADMIN_USER)
  await page.getByLabel('Пароль').fill(env.ADMIN_PASSWORD)
  await page.getByRole('button', { name: 'Войти' }).click()
  await page.getByRole('heading', { name: 'Обзор' }).waitFor({ timeout: 15000 })
  out.steps.push('вход ok')
  await page.waitForTimeout(800)
  await page.screenshot({ path: 'shots/overview.png', animations: 'disabled', timeout: 60000 })
  for (const [name, path, wait] of [['map', '/map', 'Карта'], ['events', '/events', 'События'], ['roads', '/roads', 'Дороги'], ['devices', '/devices', 'Устройства'], ['trips', '/trips', 'Поездки'], ['dictionaries', '/dictionaries', 'Справочники'], ['complaints', '/complaints', 'Жалобы'], ['access', '/access', 'Доступы'], ['brain', '/brain', 'Мозг']]) {
    await page.getByRole('link', { name: wait, exact: true }).click()
    await page.getByRole('heading', { name: wait, exact: true }).first().waitFor({ timeout: 15000 })
    await page.waitForTimeout(name === 'map' || name === 'brain' ? 2500 : 900)
    await page.screenshot({ path: `shots/${name}.png`, animations: 'disabled', timeout: 60000 })
    out.steps.push(name + ' ok')
  }
  out.errors = errors.slice(0, 10)
  return out
}
