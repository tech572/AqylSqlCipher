#
# AqylSqlCipher — CocoaPods trunk distribution
#
# SQLCipher 4.15.0 + SQLite 3.53.0 iOS binding with hidden symbol
# visibility. Companion pod to the @aqyl/comms-ios SDK.
#
# This trunk pod ships ONLY the pure-Swift wrappers + the SQLCipher
# amalgamation — NOT the Expo Module RN bridge (AqylSqlCipherModule.swift
# lives only in the @aqyl/sqlcipher npm package and requires
# ExpoModulesCore which is not on trunk). Native iOS consumers (Swift
# / Objective-C / Kotlin via KMP) get a clean, dependency-free pod.
#
# Symbol-collision protection: -fvisibility=hidden hides every
# `sqlite3_*` symbol from the amalgamation so they cannot satisfy
# another pod's link references (mirrors Android CMakeLists.txt build
# of the same amalgamation byte-for-byte).
#

Pod::Spec.new do |s|
  s.name             = 'AqylSqlCipher'
  s.module_name      = 'AqylSqlCipher'
  s.version          = '0.8.6'
  s.summary          = 'SQLCipher 4.15.0 + SQLite 3.53.0 iOS binding with hidden symbol visibility.'
  s.description      = <<~DESC
    AQYL SDK — unified SQLCipher 4.15.0 + SQLite 3.53.0 iOS binding.
    Compiles the SQLCipher amalgamation with -fvisibility=hidden so its
    sqlite3_* symbols are never exposed to the app's symbol table and
    cannot collide with other pods that link the system SQLite.
    Cipher defaults (KDF iterations, page size, HMAC algorithm) match
    the AQYL Android NDK build byte-for-byte for cross-platform schema
    compatibility.
  DESC
  s.license          = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author           = { 'AQYL' => 'tech@nowg.ai' }
  s.homepage         = 'https://github.com/tech572/AqylSqlCipher'
  s.source           = { :git => 'https://github.com/tech572/AqylSqlCipher.git', :tag => s.version.to_s }
  s.platforms        = { :ios => '13.4' }
  s.swift_versions   = ['5.9']
  s.static_framework = true

  s.source_files        = 'sqlcipher/**/*.{c,h}', '*.swift'
  s.public_header_files = 'sqlcipher/**/*.h'

  s.pod_target_xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => [
      'SQLITE_HAS_CODEC=1',
      'SQLITE_EXTRA_INIT=sqlcipher_extra_init',
      'SQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown',
      'SQLCIPHER_CRYPTO_CC=1',
      'SQLITE_TEMP_STORE=2',
      'SQLITE_THREADSAFE=1',
      'HAVE_USLEEP=1',
      'NDEBUG=1',
      'SQLITE_OMIT_LOAD_EXTENSION=1',
      'SQLITE_DEFAULT_MEMSTATUS=0',
      'SQLITE_LIKE_DOESNT_MATCH_BLOBS=1',
      'SQLITE_OMIT_DEPRECATED=1',
      'SQLITE_OMIT_PROGRESS_CALLBACK=1',
      'SQLITE_OMIT_SHARED_CACHE=1',
      'SQLITE_USE_ALLOCA=1',
      'SQLITE_OMIT_AUTOINIT=1',
      'SQLITE_DEFAULT_FILE_PERMISSIONS=0600',
      'SQLITE_ENABLE_FTS5=1',
      'SQLITE_ENABLE_RTREE=1',
      'SQLITE_ENABLE_JSON1=1',
      'CIPHER_DEFAULT_KDF_ITER=256000',
      'CIPHER_DEFAULT_HMAC_ALGORITHM=SQLCIPHER_HMAC_SHA512',
      'CIPHER_DEFAULT_PAGE_SIZE=4096',
      'CIPHER_DEFAULT_USE_HMAC=1',
      'CIPHER_DEFAULT_COMPATIBILITY=4',
    ].join(' '),
    'OTHER_CFLAGS' => [
      '$(inherited)',
      '-DSQLITE_HAS_CODEC=1',
      '-DSQLITE_EXTRA_INIT=sqlcipher_extra_init',
      '-DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown',
      '-DSQLCIPHER_CRYPTO_CC=1',
      '-fvisibility=hidden',
      '-fvisibility-inlines-hidden',
    ].join(' '),
  }
end
