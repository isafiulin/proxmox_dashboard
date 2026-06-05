String proxmoxAuthHeader({
  required String sourceType,
  required String credential,
}) {
  return switch (sourceType) {
    'proxmox_ve' => 'PVEAPIToken=$credential',
    'proxmox_backup' => 'PBSAPIToken=${_pbsCredential(credential)}',
    _ => credential,
  };
}

String _pbsCredential(String credential) {
  if (credential.contains(':')) {
    return credential;
  }

  final tokenSeparator = credential.indexOf('!');
  if (tokenSeparator == -1) {
    return credential;
  }

  final secretSeparator = credential.indexOf('=', tokenSeparator);
  if (secretSeparator == -1) {
    return credential;
  }

  return '${credential.substring(0, secretSeparator)}:'
      '${credential.substring(secretSeparator + 1)}';
}
