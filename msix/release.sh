#!/bin/sh

die () {
	echo "$*" >&2
	exit 1
}

# Evaluate architecture
ARCH="$(uname -m)"

case "$ARCH" in
i686)
	die "i686 not yet supported"
	;;
x86_64)
	BITNESS=64
	;;
*)
	die "Unhandled architecture: $ARCH"
	;;
esac

makeappx='/c/Program Files (x86)/Windows Kits/10/bin/10.0.19041.0/x64/makeappx.exe'
publisher="CN=82A13EFD-FE37-4EFC-8BA4-1C3E9EFE5F23"

version="$(powershell -Command "Write-Host (Get-Item '$(cygpath -aw /cmd/git.exe)').VersionInfo.FileVersionRaw")"
test -n "$version" || die "Could not figure out version of /cmd/git.exe"

cd "$(dirname "$0")" || die "Could not switch to working directory"

echo "Generating release notes to be included in the installer ..."
../render-release-notes.sh --css usr/share/git/ ||
die "Could not generate release notes"

etc_gitconfig="$(git -c core.editor=echo config --system -e 2>/dev/null)" &&
etc_gitconfig="$(cygpath -au "$etc_gitconfig")" &&
etc_gitconfig="${etc_gitconfig#/}" ||
die "Could not determine the path of the system config"

echo "Generating file list to be included in the installer ..."
LIST="$(printf '%s\n' git-bash.exe cmd/git-gui.exe cmd/gitk.exe cmd/git.exe)" ||
LIST="$(ARCH=$ARCH BITNESS=$BITNESS \
	ETC_GITCONFIG="$etc_gitconfig" \
	PACKAGE_VERSIONS_FILE=package-versions.txt \
	sh ../make-file-list.sh)" ||
die "Could not generate file list"

cat >PackagingLayout.xml <<EOF || die "Could not write PackagingLayout.xml"
<PackagingLayout xmlns="http://schemas.microsoft.com/appx/makeappx/2017">
  <PackageFamily ID="Git-$version" FlatBundle="false" ManifestPath="appxmanifest.xml" ResourceManager="false">
    <Package ID="Git-x64-$version" ProcessorArchitecture="x64">
      <Files>
        <File DestinationPath="Git\\etc\\package-versions.txt" SourcePath="package-versions.txt" />
        <File DestinationPath="Git\\ReleaseNotes.html" SourcePath="..\\ReleaseNotes.html" />
$(
	root="$(cygpath -aw / | sed 's|\\|&&|g')"
	echo "$LIST" | sed -e 's|/|\\|g' \
		-e '/\\WebView2Loader.dll$/d' \
		-e 's|^\(.*\)$|        <File DestinationPath="Git\\\1" SourcePath="'"$root"'\\\1" />|' \
)
        <File DestinationPath="Images\\*.png" SourcePath="Images\\*.png" />
        <File DestinationPath="Public\\Fragments\\*" SourcePath="Fragments\\*" />
      </Files>
    </Package>
  </PackageFamily>
</PackagingLayout>
EOF

cat >appxmanifest.xml <<EOF || die "Could not write appxmanifest.xml"
<?xml version="1.0" encoding="utf-8"?>

<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:mp="http://schemas.microsoft.com/appx/2014/phone/manifest"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap3="http://schemas.microsoft.com/appx/manifest/uap/windows10/3"
  xmlns:uap5="http://schemas.microsoft.com/appx/manifest/uap/windows10/5"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10"
  xmlns:desktop4="http://schemas.microsoft.com/appx/manifest/desktop/windows10/4"
  xmlns:desktop6="http://schemas.microsoft.com/appx/manifest/desktop/windows10/6"
  xmlns:iot2="http://schemas.microsoft.com/appx/manifest/iot/windows10/2" IgnorableNamespaces="mp uap uap3 uap5 rescap desktop desktop4 desktop6 iot2">

  <Identity Name="JohannesSchindelin.Git" Publisher="$publisher" Version="$version" ProcessorArchitecture="neutral"/>

  <Properties>
    <DisplayName>Git</DisplayName>
    <PublisherDisplayName>Johannes Schindelin</PublisherDisplayName>
    <Logo>Images\\StoreLogo.png</Logo>
  </Properties>

  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17134.0" MaxVersionTested="10.0.17134.0" />
    <TargetDeviceFamily Name="Windows.Universal" MinVersion="10.0.17763.0" MaxVersionTested="10.0.18362.0" />
  </Dependencies>

  <Resources>
    <Resource Language="en-us"/>
  </Resources>

  <Applications>
    <Application Id="GitBash" Executable="Git\\git-bash.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="Git Bash"
        Description="Git Bash"
        BackgroundColor="transparent"
        Square150x150Logo="Images\\Square150x150Logo.png"
        Square44x44Logo="Images\\Square44x44Logo.png">
        <uap:DefaultTile
          Wide310x150Logo="Images\\Wide310x150Logo.png"
          ShortName="Git Bash"
          Square71x71Logo="Images\\SmallTile.png"
          Square310x310Logo="Images\\LargeTile.png">
          <uap:ShowNameOnTiles>
            <uap:ShowOn Tile="square150x150Logo"/>
            <uap:ShowOn Tile="wide310x150Logo"/>
            <uap:ShowOn Tile="square310x310Logo"/>
          </uap:ShowNameOnTiles>
        </uap:DefaultTile >
        <uap:SplashScreen Image="Images\\SplashScreen.png" />
      </uap:VisualElements>
      <Extensions>
        <uap3:Extension Category="windows.appExecutionAlias" Executable="Git/git-bash.exe" EntryPoint="Windows.FullTrustApplication">
          <uap3:AppExecutionAlias>
            <desktop:ExecutionAlias Alias="git-bash.exe" />
          </uap3:AppExecutionAlias>
        </uap3:Extension>
        <uap3:Extension Category="windows.appExtension">
          <uap3:AppExtension Name="com.microsoft.windows.terminal.settings" Id="GitBash" PublicFolder="Public" DisplayName="Git Bash">
          </uap3:AppExtension>
        </uap3:Extension>
      </Extensions>
    </Application>
    <Application Id="GitGui" Executable="Git\\cmd\\git-gui.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="Git GUI"
        Description="Git GUI"
        BackgroundColor="transparent"
        Square150x150Logo="Images\\Square150x150Logo.png"
        Square44x44Logo="Images\\Square44x44Logo.png">
        <uap:DefaultTile
          Wide310x150Logo="Images\\Wide310x150Logo.png"
          ShortName="Git GUI"
          Square71x71Logo="Images\\SmallTile.png"
          Square310x310Logo="Images\\LargeTile.png">
          <uap:ShowNameOnTiles>
            <uap:ShowOn Tile="square150x150Logo"/>
            <uap:ShowOn Tile="wide310x150Logo"/>
            <uap:ShowOn Tile="square310x310Logo"/>
          </uap:ShowNameOnTiles>
        </uap:DefaultTile >
        <uap:SplashScreen Image="Images\\SplashScreen.png" />
      </uap:VisualElements>
      <Extensions>
        <uap3:Extension Category="windows.appExecutionAlias" Executable="Git/cmd/git-gui.exe" EntryPoint="Windows.FullTrustApplication">
          <uap3:AppExecutionAlias>
            <desktop:ExecutionAlias Alias="git-gui.exe" />
          </uap3:AppExecutionAlias>
        </uap3:Extension>
      </Extensions>
    </Application>
    <Application Id="Git" Executable="Git\\cmd\\git.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="Git"
        Description="Git"
        BackgroundColor="transparent"
        Square150x150Logo="Images\\Square150x150Logo.png"
        Square44x44Logo="Images\\Square44x44Logo.png"
        AppListEntry="none">
        <uap:DefaultTile
          Wide310x150Logo="Images\\Wide310x150Logo.png"
          ShortName="Git"
          Square71x71Logo="Images\\SmallTile.png"
          Square310x310Logo="Images\\LargeTile.png">
          <uap:ShowNameOnTiles>
            <uap:ShowOn Tile="square150x150Logo"/>
            <uap:ShowOn Tile="wide310x150Logo"/>
            <uap:ShowOn Tile="square310x310Logo"/>
          </uap:ShowNameOnTiles>
        </uap:DefaultTile >
        <uap:SplashScreen Image="Images\\SplashScreen.png" />
      </uap:VisualElements>
      <Extensions>
        <uap3:Extension Category="windows.appExecutionAlias" Executable="Git/cmd/git.exe" EntryPoint="Windows.FullTrustApplication">
          <uap3:AppExecutionAlias>
            <desktop:ExecutionAlias Alias="git.exe" />
          </uap3:AppExecutionAlias>
        </uap3:Extension>
      </Extensions>
    </Application>
    <Application Id="Gitk" Executable="Git\\cmd\\gitk.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="Gitk"
        Description="Gitk"
        BackgroundColor="transparent"
        Square150x150Logo="Images\\Square150x150Logo.png"
        Square44x44Logo="Images\\Square44x44Logo.png"
        AppListEntry="none">
        <uap:DefaultTile
          Wide310x150Logo="Images\\Wide310x150Logo.png"
          ShortName="Gitk"
          Square71x71Logo="Images\\SmallTile.png"
          Square310x310Logo="Images\\LargeTile.png">
          <uap:ShowNameOnTiles>
            <uap:ShowOn Tile="square150x150Logo"/>
            <uap:ShowOn Tile="wide310x150Logo"/>
            <uap:ShowOn Tile="square310x310Logo"/>
          </uap:ShowNameOnTiles>
        </uap:DefaultTile >
        <uap:SplashScreen Image="Images\\SplashScreen.png" />
      </uap:VisualElements>
      <Extensions>
        <uap3:Extension Category="windows.appExecutionAlias" Executable="Git/cmd/gitk.exe" EntryPoint="Windows.FullTrustApplication">
          <uap3:AppExecutionAlias>
            <desktop:ExecutionAlias Alias="gitk.exe" />
          </uap3:AppExecutionAlias>
        </uap3:Extension>
      </Extensions>
    </Application>
  </Applications>

  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
EOF

"$makeappx" build -o -f PackagingLayout.xml -op . -pv "$version" -bv "$version"