const RealDAO = require('./src/realdao')

if (typeof window !== 'undefined') {
  window.RealDAO = RealDAO
}

module.exports = {
  RealDAO,
}
