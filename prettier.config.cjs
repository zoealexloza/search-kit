/**
 * Prettier configuration.
 *
 * prettier-plugin-apex parses Apex with a bundled native executable by default. Where that
 * executable can't run (for example, when Windows Smart App Control blocks unsigned
 * programs), set PRETTIER_APEX_PARSER=none to use the plugin's Java parser instead. It needs
 * Java 11+ through JAVA_HOME or PATH. Without the variable, nothing changes.
 */
const apexStandaloneParser = process.env.PRETTIER_APEX_PARSER;

module.exports = {
  trailingComma: "none",
  plugins: ["prettier-plugin-apex", "@prettier/plugin-xml"],
  ...(apexStandaloneParser ? { apexStandaloneParser } : {}),
  overrides: [
    {
      files: "**/lwc/**/*.html",
      options: { parser: "lwc" }
    },
    {
      files: "*.{cmp,page,component}",
      options: { parser: "html" }
    }
  ]
};
