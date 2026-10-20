/// Элемент или качество дороги (то же правило, что в backend/brain/taxonomy.py: is_element).
///
/// Элемент — конкретная точка, о которой стоит предупредить: глубокая и опасная яма, лежачий, рельсы и переезд, люк с перепадом.
/// Мелкие и средние ямы — вклад в качество дороги: они видны в ровности участка (A–E), но точкой на карте не показываются.
bool isElement(String type, String? level) {
  switch (type) {
    case 'bump':
    case 'rail_tram':
    case 'rail_train':
      return true;
    case 'pothole':
      return level == 'deep' || level == 'danger';
    case 'manhole':
      return level == 'mid' || level == 'deep' || level == 'danger';
    default:
      return false;
  }
}

/// На всю ширину проезжей части (перестроиться бесполезно) или на одной полосе.
bool isFullWidth(String type) => type == 'bump' || type == 'rail_tram' || type == 'rail_train' || type == 'joint';
