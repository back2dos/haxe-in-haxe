// The platform packages of the npm package: hxmc's target -> npm's names
export const PLATFORMS = {
	'linux-x86_64': { pkg: '@hxmc/linux-x64', os: 'linux', cpu: 'x64', exe: 'haxe' },
	'linux-arm64': { pkg: '@hxmc/linux-arm64', os: 'linux', cpu: 'arm64', exe: 'haxe' },
	'macos-x86_64': { pkg: '@hxmc/darwin-x64', os: 'darwin', cpu: 'x64', exe: 'haxe' },
	'macos-arm64': { pkg: '@hxmc/darwin-arm64', os: 'darwin', cpu: 'arm64', exe: 'haxe' },
	'windows-x86_64': { pkg: '@hxmc/win32-x64', os: 'win32', cpu: 'x64', exe: 'haxe.exe' },
	'windows-arm64': { pkg: '@hxmc/win32-arm64', os: 'win32', cpu: 'arm64', exe: 'haxe.exe' },
};
