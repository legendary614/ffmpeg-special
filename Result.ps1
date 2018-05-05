Add-Type -Path "C:\taglib-sharp.dll"

$pathToFFprobe = "C:\Program Files\ffmpeg-4.0-win64-static\bin\ffprobe.exe"
$pathToFFmpeg = '"C:\Program Files\ffmpeg-4.0-win64-static\bin\ffmpeg.exe"'

$searchPath = "C:\Users\wolf\Downloads\Powershell Task for Gong\Powershell Task for Gong\"

$matchedExtension = @("*.mp4", "*.avi", "*.divx", "*.mov", "*.mpg", "*.wmv", "*.mkv")

function Contains-Diacritics {
	param ([String]$src = [String]::Empty)

	$normalized = $src.Normalize( [Text.NormalizationForm]::FormD )

	if ($normalized -eq $src) { 
        return $false
    }
	else { 
        Write-Output "Failed diacritics test"
        return $true 
    }
}


function Contains-IllegalCharacters {
	param ([String]$src = [String]::Empty)

	# get invalid characters and escape them for use with RegEx
	$illegal = [Regex]::Escape(-join [System.Io.Path]::GetInvalidFileNameChars())
	$pattern = "[$illegal]"

	# find illegal characters
	$invalid = [regex]::Matches($src, $pattern, 'IgnoreCase').Value | Sort-Object -Unique 

	$hasInvalid = $invalid -ne $null
	if ($hasInvalid)
	{
		Write-Output "Failed illegal file path test. File path contains: $invalid  - - for file: $src"
		return $true
	}
	else
	{
		return $false
	}
}

function Check-VideoHEVC {
	param ([String]$src = [String]::Empty)

	# https://trac.ffmpeg.org/wiki/FFprobeTips
	$ffprobeParams = '-v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "{0}"' -f $src
	Write-Output "Trying FFprobe: $pathToFFprobe $ffprobeParams"

	Start-Process -FilePath $pathToFFprobe -ArgumentList $ffprobeParams -Wait -NoNewWindow -RedirectStandardError 'D:\err.txt' -RedirectStandardOutput 'D:\out.txt'

    $codec = get-content -Path 'D:\out.txt'
    $codecError = get-content -Path 'D:\err.txt'
    Remove-Item -Path 'D:\out.txt' -Force
    Remove-Item -Path 'D:\err.txt' -Force
    Write-Output "Contents of Codec: $codec"
    Write-Output "Contents of CodecError: $codecError"

	if ($codec -ne "hevc")
	{
		Write-Output "File needs to be converted. Codec for file $src is $codec"
		return $false
	}
	else
	{
		return $true
	}
}

function Get-DifferenceInVideoRuntime {
	param ([String]$src0 = [String]::Empty,[String]$src1 = [String]::Empty)

    $video0 = [TagLib.File]::Create($src0)
    $duration0 = $video0.Properties.Duration.TotalSeconds#TotalMinutes
    
    $video1 = [TagLib.File]::Create($src1)
    $duration1 = $video1.Properties.Duration.TotalSeconds#TotalMinutes

    $Difference = $duration0 - $duration1
	if ($Difference -ne 0) {
		Write-Warning "Video run times are different by: $Difference seconds"
	}
	return $Difference
}

function Convert-VideoToHEVC {
	param ([String]$src = [String]::Empty, [String]$dst = [String]::Empty)

    $ArgumentList = '-i "{0}" -c:v libx265 -tag:v hvc1 -preset slow -x265-params “profile=main10:crf=30” -c:a aac -b:a 128k -c:s mov_text "{1}"' -f $src, $dst

    # Display the command line arguments, for validation
    Write-Host -ForegroundColor Green -Object $ArgumentList
    # Pause the script until user hits enter
    # $null = Read-Host -Prompt 'Press enter to continue, after verifying command line arguments.'

    # Kick off ffmpeg
    Start-Process -FilePath $pathToFFmpeg -ArgumentList $ArgumentList -Wait -NoNewWindow -RedirectStandardError 'D:\err.txt' -RedirectStandardOutput 'D:\out.txt'

    $outputData = get-content -Path 'D:\out.txt'
    $errorData = get-content -Path 'D:\err.txt'
    Remove-Item -Path 'D:\out.txt' -Force
    Remove-Item -Path 'D:\err.txt' -Force
    Write-Output "Contents of Codec: $outputData"
    Write-Output "Contents of CodecError: $errorDat"

    if (Get-DifferenceInVideoRuntime $src $dst -lt 1)
	{
        $etclist = Get-ChildItem -Path $path -Recurse -Filter "*sample*"
        foreach ($file in $etclist) {
	        Write-Output $file
        }

		Write-Output "New movie created: $((Get-Item $dst).length/1GB) GB - - $dst"
		Write-Output "Deleting original file: $((Get-Item $src).length/1GB) GB  - - $src"
		Remove-Item $src -Force
		return $true;
	}
	else
	{
		Remove-Item $dst -Force
		Write-Output "WARNING: Conversion might have failed. Deleting potential unfinished file: $dst"
		return $false; 
	}
}

Write-Output "Scanning drive $searchPath for all files matching $matchedExtension and ordering from largest to smallest."

$filelist = Get-ChildItem -Include $matchedExtension -Path $searchPath -Recurse | ? { $_.GetType().Name -eq "FileInfo" } | sort-Object -property length -Descending

foreach ($file in $filelist)
{
	Write-Output "--------------  Start New File  --------------"

	$srcFileName = $file.BaseName + $file.Extension
	$source = $file.DirectoryName + "\" + $srcFileName
    $dstFileName = $file.BaseName.Replace("264","265") + "_h265"
    $destination = $file.DirectoryName + "\" + $dstFileName + ".mp4"
    
	Write-Output "Source Path: $source, Destination: $destination"

    $isDiacritics = Contains-Diacritics $fileName
	Write-Output "Testing Diacritics: $isDiacritics"

	$isIllegalCharacters = Contains-IllegalCharacters $fileName
	Write-Output "Testing Illegals: $isIllegalCharacters"

	$isVideoHEVC = Check-VideoHEVC $source
	Write-Output "Testing Video Codec: $isVideoHEVC"

	$needToConvert = $true

    if ($isDiacritics -eq $true) { 
		Write-Output "File containts diacritic characters that cause problems, skipping. Offending file: $source"
		$needToConvert = $false
	}
	if ($isIllegalCharacters -eq $true) { 
		Write-Output "File containts illegal characters that cause problems, skipping. Offending file: $source" 
		$needToConvert = $false
	}
	if ($isVideoHEVC -eq $true) { 
		Write-Output "File is already converted to HEVC, skipping. Offending file: $source" 
		$needToConvert = $false
	}

    if ($needToConvert) {

		if (Convert-VideoToHEVC $source $destination -eq $true) {
            $basename = $file.BaseName + ".*"
            $etclist = Get-ChildItem -Path $searchPath -Recurse -Filter $basename
            foreach ($etc in $etclist) {
                if ($etc.BaseName + $etc.Extension -eq $srcFileName) {        
		            # Write-Output "same" 
                }
                else {
	                # Write-Host $etc
                    $orgPath = $etc.DirectoryName + "\" + $etc.BaseName + $etc.Extension
                    $dstPath = $etc.DirectoryName + "\" + $dstFileName + $etc.Extension
                    Rename-Item $orgPath $dstPath -force
                }
            }
			Write-Host -ForegroundColor Green -Object "Conversion successful!"
		}
		else {

			Write-Host -ForegroundColor Green -Object "Conversion failed!"
		}
	}
}