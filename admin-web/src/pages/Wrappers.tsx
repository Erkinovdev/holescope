import { PageHeader } from '../components/ui'
import { ParamsTab, QueueTab, UploadsTab } from './Brain'
import { CarModels } from './Dictionaries'

export function Questions() {
  return <div><PageHeader title="Вопросы" sub="События, по которым нужен ответ: что это было — яма, люк, рельсы или шум" /><QueueTab /></div>
}
export function Memory() {
  return <div><PageHeader title="Память · CSV" sub="Сырые записи датчиков: загрузка, разбор и проверка алгоритмом" /><UploadsTab /></div>
}
export function Algo() {
  return <div><PageHeader title="Алгоритм" sub="Пороги и параметры правил, версии и предпросмотр на записи" /><ParamsTab /></div>
}
export function Cars() {
  return <div><PageHeader title="Автомобили" sub="Справочник моделей: колёсная база, шины, источник данных и накопленная «мягкость»" /><CarModels /></div>
}
