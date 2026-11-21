const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper,
    // Records Navigate / GenerateUrl calls; the default stub does not.
    "^lightning/navigation$": "<rootDir>/jest-mocks/lightning/navigation"
  },
  setupFilesAfterEnv: [
    ...(jestConfig.setupFilesAfterEnv || []),
    "<rootDir>/jest-sa11y-setup.js"
  ],
  // The preset's absolute coverage globs don't match on Windows; relative ones do.
  collectCoverageFrom: [
    "{force-app,demo}/**/lwc/**/*.js",
    "!**/lwc/**/__tests__/**"
  ],
  // Babel (istanbul) coverage reports 0% on Node 26 (bundled with the sf CLI); V8 works.
  coverageProvider: "v8",
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};
