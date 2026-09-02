// Lectura y escritura de claves anidadas ("output.min").
//
// El esquema declara algunas claves con punto porque así viven en el config
// que guarda el dominio (`{"output":{"min":0}}`). El editor no las aplana: las
// recorre, para que lo que se guarda sea exactamente lo que el modelo lee.
export function readNested(object, key) {
  return String(key).split('.').reduce((node, segment) => (
    node && typeof node === 'object' ? node[segment] : undefined
  ), object);
}

export function writeNested(object, key, value) {
  const segments = String(key).split('.');
  const last = segments.pop();
  const node = segments.reduce((acc, segment) => {
    if (typeof acc[segment] !== 'object' || acc[segment] === null) acc[segment] = {};
    return acc[segment];
  }, object);
  node[last] = value;
  return object;
}
