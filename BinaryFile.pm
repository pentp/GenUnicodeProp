# ==++==
# 
#   Copyright (c) Microsoft Corporation.  All rights reserved.
# 
# ==--==
package BinaryFile;

our $g_bigEndian = 0;    # 0 == Little Endian. 1 == Big Endian.

###############################################################################
#
# WriteByte
#
# Parameters:
#   $hFile  FILEHANDLE to use
#   $value  The byte value to be written
#
# Returns:
#   None
#
# Notes:
#   This function will check if the $value to be written is within the byte value range.
#
###############################################################################

sub WriteByte
{
    my $hFile = shift;
    my $value = shift;
    if ($value > 0xff)
    {
        printf "WriteByte(): value 0x[%04X] exceeds byte range.\n", $value;
        exit(1);
    }
    syswrite $hFile, pack('C', $value); # 'C' for unsigned char
}

sub GetByte
{
    my ($value) = @_;
    if ($value > 0xff || $value < 0)
    {
        printf "GetByte(): value 0x[%04X] exceeds byte range.\n", $value;
        exit(1);
    }
    return (pack('C', $value));    
}


sub WriteMultiBytes
{
    my ($hFile, $value, $length) = @_;
    my $i;
    for ($i = 0; $i < $length; $i++)
    {
        WriteByte($hFile, $value);
    }
}

###############################################################################
#
# WriteWord
#
# Parameters:
#   $hFile  FILEHANDLE to use
#   $value  The word value to be written
#
# Returns:
#   None
#
# Notes:
#   This function will check if the $value to be written is within the word value range.
#
###############################################################################

sub WriteWord
{
    my ($hFile, $value) = @_;
    if ($value > 0xffff)
    {
        printf "WriteWord(): value 0x[%08X] exceeds word range.\n", $value;
        exit(1);
    }
    syswrite $hFile, GetWordBytes($value); # "S" for unsigned
}

sub GetWordBytes
{
    my ($value) = @_;
    if ($value > 0xffff || $value < 0)
    {
        printf "GetWordBytes(): value 0x[%08X] exceeds word range.\n", $value;
        exit(1);
    }
    return pack(($g_bigEndian ? 'n': 'S'), $value); # "S" for unsigned
}


sub GetSignedWordBytes
{
    my ($value) = @_;
    if ($value > 32767 || $value < -32768)
    {
        printf "GetSignedWordBytes(): value 0x[%08X] exceeds word range.\n", $value;
        exit(1);
    }
    return pack(($g_bigEndian ? 'n': 'S'), $value); # "S" for unsigned
}


###############################################################################
#
# WriteDWord
#
# Parameters:
#   $hFile  FILEHANDLE to use
#   $value  The dword value to be written
#
# Returns:
#   None
#
# Notes:
#   This function will check if the $value to be written is within the dword value range.
#
###############################################################################

sub WriteDWord
{
    my ($hFile, $value) = @_;
    if ($value > 0xffffffff)
    {
        printf "WriteDWord(): value 0x[%08X] exceeds word range.\n", $value;
        exit(1);
    }
    syswrite $hFile, pack(($g_bigEndian ? 'N': 'L'), $value); # "S" for unsigned
}

sub GetDWordBytes
{
    my ($value) = @_;

    if ($value > 0xffffffff)
    {
        printf "WriteDWord(): value 0x[%08X] exceeds word range.\n", $value;
        exit(1);
    }
    return (pack(($g_bigEndian ? 'N': 'L'), $value));
}

###############################################################################
#
# WriteByteString
#
# Parameters:
#   
#   
# Returns:
#   None
#
#
###############################################################################

sub WriteByteString
{
    my $hFile = shift;
    my $str = shift;
    my @byteArray = split /[ \n]/, $str;
    foreach my $byte (@byteArray)
    {
        syswrite $hFile, pack("C", $byte);
    }
}

sub GetWideStringBytes
###############################################################################
#
# Write a Unicode String using a ASCII string parameter.
#
# Parameters:
#   
#   
# Returns:
#   None
#
#
###############################################################################
{
    my ($str) = @_;

    my $bytes = "";
    for ($i = 0; $i < length($str); $i++) 
    {
        if ($g_bigEndian)
        {
            $bytes = $bytes . pack("C", 0);
        }
        $bytes = $bytes . pack('a', substr($str, $i, 1));
        if (!$g_bigEndian)
        {
            $bytes = $bytes . pack("C", 0);
        }
    }
    $bytes = $bytes . pack("S", 0);
    return ($bytes);
}

sub WriteWideString
###############################################################################
#
# Write a Unicode String using a ASCII string parameter.
#
# Parameters:
#   
#   
# Returns:
#   None
#
#
###############################################################################
{
    my ($hFile, $str) = @_;

    for ($i = 0; $i < length($str); $i++) 
    {
        if ($g_bigEndian)
        {
            WriteByte($hFile, 0);
        }
        syswrite $hFile, pack('a', substr($str, $i, 1));
        if (!$g_bigEndian)
        {
            WriteByte($hFile, 0);
        }
    }
    WriteWord($hFile, 0);
}

sub WriteFixedWideString
###############################################################################
#
# Write a fixed-length Unicode String using a ASCII string parameter.
#
# Parameters:
#   
#   $length The length of string in WCHAR (including NULL).
# Returns:
#   None
#
#
###############################################################################{
{
    my ($hFile, $str, $length) = @_;
    if ($length < length($str) + 1)
    {
        die "[$str] is too long";
    }
    WriteWideString($hFile, $str);
    my $i;
    for ($i = 0; $i < ($length - length($str) - 1); $i++)
    {
        WriteWord($hFile, 0);
    }
}



sub GetFixedUnicodeStringBytes
{
    my ($str, $length) = @_;
    my $bytes = "";
    if ($length < length($str) + 1)
    {
        die "GetFixedUnicodeStringBytes(): [$str] is too long";
    }
    $bytes = GetWideStringBytes($str);
    my $i;
    for ($i = 0; $i < ($length - length($str) - 1); $i++)
    {
        $bytes = $bytes . GetWordBytes(0);
    }

    return ($bytes);
}

sub GetByteBoundary
{
    my ($byteBoundary, $offset) = @_;
    my $remainder = ($offset % $byteBoundary);
    if ($remainder == 0) 
    { 
        return 0; 
    }
    return $byteBoundary - $remainder;
 
}
sub WriteByteBoundary
{
    my ($hFile, $byteBoundary, $offset, $byteToFill) = @_;

    my $byteCount = GetByteBoundary($byteBoundary, $offset);

    my $i;
    for ($i = 0; $i < $byteCount; $i++)
    {
        WriteByte($hFile, $byteToFill);
    }
    return ($byteCount);
}

sub GetByteBoundaryBytes
{
    my ($byteBoundary, $offset, $byteToFill) = @_;

    my $str = "";
    my $byteCount = GetByteBoundary($byteBoundary, $offset);

    my $i;
    for ($i = 0; $i < $byteCount; $i++)
    {
        $str = $str . GetByte($byteToFill);
    }
    return ($str);
}

sub WriteDouble
{
    my ($hFile, $doubleValue) = @_;
    syswrite $hFile, $g_bigEndian ? reverse pack("d", $doubleValue) : pack("d", $doubleValue);

    return (4);
}

sub GetDoubleBytes
{
    my ($doubleValue) = @_;
    return ($g_bigEndian ? reverse pack("d", $doubleValue) : pack("d", $doubleValue));
}


1;
