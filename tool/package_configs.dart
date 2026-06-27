/// Hardcoded package metadata for release tooling that has not yet adopted
/// `--cwd`. Used by `wait_for_pub_dev_version.dart`.
const packageConfigs = <String, PackageConfig>{
  'foundry_core': PackageConfig(
    packagePath: 'packages/foundry_core',
    versionConstName: 'foundryCoreVersion',
  ),
  'foundry_cli': PackageConfig(
    packagePath: 'packages/foundry_cli',
    versionConstName: 'foundryCliVersion',
  ),
};

class PackageConfig {
  const PackageConfig({
    required this.packagePath,
    required this.versionConstName,
  });

  final String packagePath;
  final String versionConstName;
}
