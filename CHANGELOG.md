# Changelog
All notable changes to this project will be documented in this file.

## [Unreleased]

## [2.2.0] - 2016-01-19
### Changed
- Revert previous change to FRIENDLY_NAME. The default is `hostname` again. #13
- Place core script functionality toward top of script. #10
### Fixed
- dpkg-query no longer includes packages not in the fully installed state. #9
### Added
- Provide user with information on machine metadata. #12
- Display UUID file location.

## [2.1.0] - 2016-01-15
### Changed
- Default FRIENDLY_NAME is now the string `testing`
### Deprecated
- CLEANSWEEP_UUID is now PATCHWORK_UUID.

## [2.0.1] - 2016-01-13
### Fixed
- curl data is no longer passed as command line argument. #8 (@TheHippo)
- Wrapped script in function. #7 (@DoubleMalt, @SchizoDuckie)

## [2.0.0] - 2016-01-13
### Changed
- API_TOKEN is now PATCHWORK_API_KEY

## [1.1.2] - 2016-01-12
### Fixed
- Fixed duplicate registration message

## [1.1.1] - 2016-01-12
### Fixed
- Fixed initial registration error

## [1.1.0] - 2016-01-11
### Added
- Allow user to specify UUID through command line #4

### Changed
- Improve error messages when run on unsupported operating system
