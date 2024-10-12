# Debugging issues

## MacOS

Loon uses the [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) package for storing an encryption key on different platforms. If using encryption, you have to ensure that you enable [keychain sharing on MacOS](https://github.com/mogol/flutter_secure_storage/issues/350#issuecomment-1097123273).