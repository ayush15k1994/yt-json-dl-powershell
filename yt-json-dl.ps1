# Get-ChildItem json | %{.\yt-json-dl.ps1 -video_id $_.BaseName >> "download_log.txt"}

# Get-Content .\yt-urls.txt | ForEach-Object { yt-dlp $_ -j > json/$($_.Substring($_.IndexOf("=")+1)).json }

<#
    filename: {video title} [{video id}] - [{video quality}]
        video quality = {vcodec number}+{acodec number} 

    formats
        format_id - the number we choose for selecting download streams
        format_note - audio quality qualifier (Default, ultralow, low, medium), video quality qualifier (eg., 144p, 720p60, 1080p60)
        ext - file/format extension
        video_ext - video format extension or none
        audio_ext - audio format extension or none
        resolution - for video: 256x144, 1280x720 etc., for audio: audio only
        container - container type for stream

        more info: 

    subtitles: name, format (ext)

    chapters
#>

<#
    selecting an appropriate audio and video stream:
    preferred format: vformat, aformat
    preferred resolution: from format_note
#>

# $formats = $formats | ?{ $_.format_note -ne 'storyboard' }
# $video_streams = $formats | ?{ $_.video_ext -ne 'none' }
# $audio_streams = $formats | ?{ $_.audio_ext -ne 'none' }

<#
    video name default: <video_title> [<video_id>].<container_ext>
    video name required: <video_title> [<video_id>] [<video_format_id>]x[<audio_format_id>].<container_ext>
#>

param(
    [Parameter(Mandatory=$true)]
    [String]$video_id,

    [String]$json_folder="json",
    [String]$download_folder="youtube"
)

$preferred_audio_format = "m4a";
$preferred_video_format = "mp4";
$preferred_video_resolution = 1280;

$jsonFile = "";

if ($video_id.Trim().Length -eq 0 -or $video_id.Trim().StartsWith("#")) {
    Write-Host "Exiting commented or empty video: $video_id";
    exit;
}

if ($video_id.StartsWith("https:")) {
    if ($video_id.Contains("&")) {
        $video_id = $video_id.Substring(0, $video_id.IndexOf("&"));
    }
    $jsonFile = yt-dlp $video_id -j;
} else {
    $jsonFile = Get-Content "$json_folder/$video_id.json";
}

$json = $jsonFile | ConvertFrom-Json;
$formats = $json.formats;
$video_url = $json.original_url;
$video_title = $json.title;
$channel_name = $json.channel;

# $storyboards = $formats | Where-Object{ $_.format_note -eq 'storyboard' };
$audios = $formats | Where-Object{ $_.audio_ext -ne 'none' };
$videos = $formats | Where-Object{ $_.video_ext -ne 'none' };

$best_audio = $audios[-1]
$selected_audio_id = $best_audio.format_id;
$selected_audio_formats = $best_audio.format_note;
if ($selected_audio_id.Contains("-")) {
    $base_audio_id = $selected_audio_id.Substring(0, $selected_audio_id.IndexOf("-"));
    $best_audio = $audios | Where-Object{ $_.format_id.StartsWith($base_audio_id) };
    $selected_audio_formats = ($best_audio | ForEach-Object{$_.format_note}) -join "`n";
    $selected_audio_id = ($best_audio | ForEach-Object{$_.format_id}) -join "+";

    # TODO: naming multiple audio formats correctly, currently all are named as Track1, Track2 etc.
}

# choose suitable video
$selected_videos = $videos | Where-Object{$_.width -eq $preferred_video_resolution -and $_.ext -eq $preferred_video_format};
if ($selected_videos.Length -eq 0) {
    $selected_videos = $videos | Where-Object{$_.width -eq $preferred_video_resolution};
}
if ($selected_videos.Length -eq 0) {
    $selected_videos = $videos[-1];
}

$selected_video_id = $selected_videos[-1].format_id;
$resolution = $selected_videos[-1].resolution;

$subs = "";
if ($null -ne $json.subtitles) {
    $subs = $json.subtitles.psobject.Properties.Name.Where{$_.StartsWith("en") -or $_.StartsWith("ko") -or $_.StartsWith("ja") -or $_.StartsWith("zh")};
    $subs = $subs -join ',';
}


Write-Host "No. of Audio Tracks: " $best_audio.Length;

# $selected_video_id
# $selected_audio_id

$video_filename = yt-dlp $video_url  $(if($best_audio.Length -gt 1) {"--audio-multistreams"} ) -f "$($selected_video_id)+$($selected_audio_id)" -o "$download_folder/%(title)s [%(id)s] [$selected_video_id+$selected_audio_id] $resolution.%(ext)s" --get-filename;
$video_ext = $video_filename.Substring($video_filename.LastIndexOf("."));
Write-Host "Downloading video: $video_title [$video_url] from $channel_name - `nselected video: ${selected_video_id}: ${resolution} `nselected audio: ${selected_audio_id}`n$selected_audio_formats as:`n${video_filename}"
yt-dlp $video_url  $(if($best_audio.Length -gt 1) {"--audio-multistreams"} ) -f "$($selected_video_id)+$($selected_audio_id)" -o "$download_folder/%(title)s [%(id)s] [$selected_video_id+$selected_audio_id] $resolution" --embed-thumbnail --convert-thumbnail png --embed-chapters --embed-subs --sub-langs $subs 
# | Tee-Object -Variable output
# Write-Host "yt-dlp $video_url  $(if($best_audio.Length -gt 1) {"--audio-multistreams"} ) -f $($selected_video_id)+$($selected_audio_id) -o  $download_folder/%(title)s [%(id)s] [$selected_video_id+$selected_audio_id] $resolution --embed-thumbnail --convert-thumbnail png --embed-chapters --embed-subs --sub-langs $subs"

# Postprocessing to rename audio tracks with language
if ($best_audio.Length -gt 1) {
    # $video_filename = $output | Where-Object{$_.StartsWith("[Merger]")};
    # $video_filename = $video_filename.Substring($video_filename.IndexOf("`"")+1, $video_filename.LastIndexOf("`"")-$video_filename.IndexOf("`"")-1);
    # $video_filename = $video_filename.Replace("\", "/");

    Write-Host "Renaming Audio Streams for ${video_filename}"
    $metadata_map = [System.Collections.ArrayList]::new();
    $disposition_map = [System.Collections.ArrayList]::new();
    $defaulted = $false;
    for ($i=0; $i -lt $best_audio.Length; $i++) {
        $track_title = $best_audio[$i].format_note;
        if ($track_title.Contains(",")) {
            $track_title = $track_title.Substring(0, $track_title.IndexOf(",")).Trim();
        }
        $track_language = $best_audio[$i].language;
        if ($track_language.StartsWith("en") -and -not $defaulted) {
            $defaulted = $true;
            Write-Host "Setting default audio track to stream ${i}: ${track_title} : ${track_language}"
            $disposition_map.Add("-disposition:a:${i}");
            $disposition_map.Add("0");
            
            $disposition_map.Add("-disposition:a:${i}");
            $disposition_map.Add("default");
        } else {
            $disposition_map.Add("-disposition:a:${i}");
            $disposition_map.Add("0");
        }
        Write-Host "Stream ${i}: Title=${track_title} ; Language=${track_language}";
        # $metadata_map = $metadata_map + " -metadata:s:a:${i} title=`"${track_title}`" -metadata:s:a:${i} language=`"${track_language}`"";
        $metadata_map.Add("-metadata:s:a:${i}");
        $metadata_map.Add("title=${track_title}");
        $metadata_map.Add("-metadata:s:a:${i}");
        $metadata_map.Add("language=${track_language}");
    }

    Write-Host "ffmpeg -i" "'${video_filename}'" "-map 0 -c copy" "${metadata_map}" "${download_folder}/metadata${video_ext}"
    ffmpeg -i "${video_filename}" -map 0 -c copy @metadata_map @disposition_map "${download_folder}/metadata${video_ext}"

    Write-Host "removing item: ${video_filename}";
    $x = Remove-Item -LiteralPath "${video_filename}" -Force;
    Write-Host "Removed item: $x";
    Move-Item -Path "${download_folder}/metadata${video_ext}" -Destination "${video_filename}";
}

Write-Host "========================================================";