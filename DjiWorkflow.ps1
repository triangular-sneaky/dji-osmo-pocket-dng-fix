[CmdletBinding()]
param (
    [string]$FolderSlug = "dji",
    [string]$DcimPath = "/Volumes/Untitled/DCIM",
    [string]$InboxPath = "/Users/k/_work/__INBOX/",
    [string]$VideoPath = "/Users/k/_work/DJI/DJI videos",

    [string]$DuplicateFileSlug = "--"
)

. (Join-Path $PSScriptRoot ./DjiPatcher.ps1);




$sourceFolders = Get-ChildItem -Directory $DcimPath -Filter "*MEDIA";
$newFolderBaseName = "$(get-date -Format "yyyy-MM-dd")-$($FolderSlug)";
$pathInInbox = (join-path $InboxPath $newFolderBaseName);
$pathInVideo = (join-path $VideoPath $newFolderBaseName);


$destFolders = $sourceFolders | %{ 

    $i=-1;
    do {
        $i = $i + 1;
        if ($i) {$suffix = "-$i";}
        $newFolderName = "$($newFolderBaseName)$($suffix)";
        $newPath = (Join-Path $DcimPath $newFolderName);
    } while (test-path $newPath);
 
  
    Write-Host "Processing $_`nrename:`t$newPath`ninbox:`t$pathInInbox`nvideo:`t$pathInVideo";

    Move-Item $_ $newPath;




    rsync -rtb --suffix "$($DuplicateFileSlug)$i" (join-path $newPath "*") "$pathInInbox/";

    Get-ChildItem $pathInInbox -filter "*$DuplicateFileSlug*" | %{ 
        $newName = $_.FullName -replace "(\..+)($DuplicateFileSlug.*)`$",'$2$1'
        Move-Item $_ $newName;
    }


    
    return @{pathInInbox=$pathInInbox;pathInVideo=$pathInVideo};
};

try {
        
    Push-Location $pathInInbox;


    get-childitem $pathInInbox | Where-Object Name -match DJI_\d+\.dng | Foreach-WithProgress{ Patch-DjiDngOpCodeList3 $_.Name };

    write-debug "$pathInInbox ~> '$pathInVideo'";
    
    new-item -ItemType Directory $pathInVideo -Force; #v(join-path $pathInInbox "*")
    # & rsync ("-avv","--include='*.mp4'","--include='*.MP4'","'$pathInInbox'","'$pathInVideo'");

    Copy-Item (Join-Path $pathInInbox "*.MP4") $pathInVideo ;

    new-item -ItemType SymbolicLink -Force (Join-Path $InboxPath "_LATEST") -Value $pathInInbox;

} finally {
    Pop-Location;
}

