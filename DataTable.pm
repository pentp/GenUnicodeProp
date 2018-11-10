use BinaryFile;

###############################################################################
#
# class DataTable
#
# This class can be used to generate different types of sub-tables for NLS+
# data tables.
#
###############################################################################

package DataTable;

my $MaxUTF32 = 0x10ffff;

sub New
###############################################################################
#
#   Actions:
#       Create an instance of DataTable.
#
#   Returns:
#        An instance of DataTable
#
#   Parameters:
#       $endian         Specify the endianess of the table.
#       $tableType      Specify different types of table
#           1           Flat table
#           2           Counted flat table
#           8           8:4:4 table
#           12          12:4:4 table
#       $defaultValue   The default value for unspecified index.
#       $valueByteSize  The size in byte for the value to be written to the table.
#
###############################################################################
{
    my ($endian, $tableType, $defaultValue, $valueByteSize, $pGetValueBytesCallback) = @_;

    my $self = {};

    #
    # Define instance variables for this class.
    #

    # This indicates if we should emit a big-Endian or little-Endian table.
    # 0 => little-Endian
    # 1 => Big-Endian
    $self->{m_endian} = $endian;            
    if ($tableType == 1 || $tableType == 2 || $tableType == 8 || $tableType == 12)
    {
        $self->{m_tableType} = $tableType;
    } else 
    {
        die "DataTable::New(): Invalid table type [$tabelType].";
    }

    # If a codepoint does not have data, this specifies the default value.    
    $self->{m_defaultValue} = $defaultValue;
    #if (($tableType == 8 || $tableType == 12) && $valueByteSize != 2)
    #{
    #    die "DataTable::DataTable(): The valueByteSize other than 2 are not supported yet for 8:4:4 or 12:4:4 table.";
    #}
    
    $self->{m_valueByteSize} = $valueByteSize;
    $self->{m_pGetValueBytesCallback} = $pGetValueBytesCallback;

    # This contains the data mapping between codepoints and values.
    $self->{m_rawData} = [];                

    # To indicate how many characters for a specific plane.  Should contain 17 elements for plane 0 ~ 16.    
    $self->{m_planeCharCountArray} = [];

    # To indicate if a verbose output should be generated in GenerateTable().
    $self->{m_verbose} = 0;

    # The following are all 2-dimentional array.  
    # The first dimention is the plane, and the second dimention is the index or values for that plane.
    $self->{m_level1Index} = [];        
    $self->{m_level2Index} = [];
    $self->{m_level3Data} = [];

    # The total index table size for every plane.
    $self->{m_pPlaneTableSize} = [];    

    $self->{m_bytes} = "";
    $self->{m_offset} = 0;
    
    bless ($self);
    return ($self);
}

sub SetVerbose
{
    my ($self, $verbose) = @_;
    $self->{m_verbose} = $verbose;
}

sub GetEndian
{
    my ($self) = @_;
    return ($self->{m_endian});
}

sub GetRawDataElement
{
    my ($self, $index) = @_;
    return ($self->{m_rawData}->[$index]);
}

# public
sub CopyData
###############################################################################
#
# Copy Raw data from another instance of DataTable
#
###############################################################################
{
    my ($self, $pDataTable) = @_;

    for ($i = 0; $i <= $#{$pDataTable->{m_rawData}}; $i++)
    {
        push @{$self->{m_rawData}}, $pDataTable->{m_rawData}->[$i];
    }
}

sub GetData
{
    my ($self, $codepoint) = @_;

    return ($self->{m_rawData}->[$codepoint]);
}



sub AddData
###############################################################################
#
#   Actions:
#       Add the value data for the specified codepoint.
#
#   Returns:
#        None
#
#   Parameters:
#        $codepoint    The codepoint to be added
#        $value        The value for the specified codepoint
#
###############################################################################
{
    my ($self, $codepoint, $value) = @_;

    $self->{m_rawData}->[$codepoint] = $value;

    $self->{m_planeCharCountArray}->[$codepoint >> 16]++;
}

# private
sub GenerateTable12_4_4
###############################################################################
#
#   Actions:
#       Create the 12:4:4 data table structure after all the codepoint/value pairs are
#       added by using AddData.
#
#   Returns:
#        None
#
#   Parameters:
#        None
#
###############################################################################
{
    my ($self) = @_;

    my $i;
    my $j;
    my $k;
    my $ch = 0;
    
    
    # There is data in the plane.  Create 8:4:4 table for this plane.
    

    my %level2Hash = {};
    my %level3Hash = {};

    $self->{m_level1Index} = [];
    $self->{m_level2Index} = [];

    my $planes;

    if ($self->{m_tableType} == 8) 
    {
        $planes = 1;
        print "Process 8:4:4 table.\n";
    } elsif ($self->{m_tableType} == 12)
    {
        $planes = 17;
        print "Process 12:4:4 table.\n";
    } else
    {
        die "DataTable::GenerateTable12_4_4: Invalid table type. The value should be 8 or 12.";
    }    
    
    # Process plan 0 ~ 16.
    for ($i = 0; $i < 256 * $planes; $i++)
    {
        # Generate level 1 indice

        # This is the row data which contains a row of indice for level 2 table.
        my $level2RowData = "";
        for ($j = 0; $j < 16; $j++) 
        {
            # Generate level 2 indice
            my $level3RowData = "";
            for ($k = 0; $k < 16; $k++) 
            {
                # Generate level 3 values by grouping 16 values together.
                # Each element of the 16 value group is seperated by ";"
                my $value = $self->{m_rawData}->[$ch];
                if (defined($value)) 
                {
                    # There is data defined for this codepoint.  Use it.
                    $level3RowData = $level3RowData . $value . ";";
                } else 
                {
                    # There is no data defined for this codepoint.  Use the default value
                    # specified in the ctor.
                    $level3RowData = $level3RowData . $self->{m_defaultValue} . ";";
                }
                $ch++;
            }

            # Check if the pattern of these 16 values happens before.
            my $valueInHash = $level3Hash{$level3RowData};

            my $isNewData;  # Used in verbose output to indicate if this is a new group of 16 values.
            
            if (!defined($valueInHash))
            {
                # This is a new group in the level 3 values.
                # Get the current count of level 3 group count for this plane.
                $valueInHash = $#{$self->{m_level3Data}} + 1;
                # Store this count to the hash table, keyed by the pattern of these 16 values.
                $level3Hash{$level3RowData} = $valueInHash;

                # Populate the 16 values into level 3 data table for this plane.
                my @values = split(/;/, $level3RowData);
                push @{$self->{m_level3Data}}, @values;
               
                $isNewData = "NEW";
            } else
            {
                # This is an existing row in the level 3 data table.
                $isNewData = "   ";
            }
            if ($self->{m_verbose}) 
            {
                printf "       Level 3: $isNewData [$level3RowData], Index = %04x\n", $valueInHash;
            }
            $level2RowData = $level2RowData . sprintf("%04x", $valueInHash) . "," ;
        }
        my $valueInHash = $level2Hash{$level2RowData};

        my $isNewData;
        if (!defined($valueInHash))
        {
            # Get the count of the current level 2 index table.
            $valueInHash = ($#{$self->{m_level2Index}} + 1)/16;
            $level2Hash{$level2RowData} = $valueInHash;
            
            # Populate the 16 values into level 2 data table for this plane.
            push @{$self->{m_level2Index}}, split(/,/, $level2RowData);
            $isNewData = "NEW";
        } else
        {
            $isNewData = "   ";
        }
        if ($self->{m_verbose}) 
        {
            printf "   Level 2: $isNewData [$level2RowData], Index = %04x\n", $valueInHash;
        }
        # Populate the index values into level 1 index table.
        push @{$self->{m_level1Index}}, $valueInHash;
    }

    if ($self->{m_verbose}) 
    {
        printf "Level 1:";
        for ($i = 0; $i < 256; $i++)
        {
            printf("%02x,", $self->{m_level1Index}->[$i]);
        }
        print "\n";
    }
    my $level1Count = ($#{$self->{m_level1Index}} + 1);
    my $level2Count = ($#{$self->{m_level2Index}} + 1);
    my $level3Count = ($#{$self->{m_level3Data}} + 1);

    print "level 1: $level1Count\n";
    print "level 2: $level2Count\n";
    print "level 3: $level3Count\n";
    
    $self->{m_pPlaneTableSize} 
        = $level1Count * 1 +    # Level 1 index value is BYTE.
          $level2Count * 2 +    # Level 2 index value is WORD.
          $level3Count * $self->{m_valueByteSize};
    print $self->{m_pPlaneTableSize} ;
    print "\n";
    
}

# private
sub GenerateTable_CountFlat
###############################################################################
#
# Generate a flat table with a WORD count in the front.
#
###############################################################################
{
    my ($self) = @_;

    printf "Process counted flat table.\n";
    $self->{m_flatMaxItem} = $#{$self->{m_rawData}};
}


# private
sub GenerateTable_Flat
###############################################################################
#
# Generate a flat table
#
###############################################################################
{
    my ($self) = @_;

    printf "Process flat table\n";
    $self->{m_flatMaxItem} = $#{$self->{m_rawData}};
}

# public
sub GenerateTable
###############################################################################
#
# Generate the table structure according to different table types.
#
###############################################################################
{
    my ($self) = @_;
    if ($self->{m_tableType} == 1)
    {
        GenerateTable_Flat($self);
    } elsif ($self->{m_tableType} == 2)
    {
        GenerateTable_CountFlat($self);
    } elsif ($self->{m_tableType} == 8)
    {
        GenerateTable12_4_4($self);
    } elsif ($self->{m_tableType} == 12)
    {
        GenerateTable12_4_4($self);
    } else 
    {
        die "DataTable::Generate(): Invalid table type $slef->{m_tableType}\n";
    }
}

sub AddBytes
{
    my ($self, $str) = @_;

    $self->{m_bytes} = $self->{m_bytes} . $str;
    $self->{m_offset} += length($str)
}

sub GetBytesFlat
{
    my ($self, $offset, $pCallback) = @_;

    my $i;
    my $str;
    for ($i = 0; $i <= $self->{m_flatMaxItem}; $i++)
    {
        my $value = $self->{m_rawData}->[$i];
        if (!defined($value))
        {
            $value = $self->{m_defaultValue};
        }
        $str = $str . $self->{m_pGetValueBytesCallback}->($value);
    }
    return ($str);
}


sub GetBytesCountedFlat
###############################################################################
#
# Get the real byte contents for the counted flat table.
# The counted flat table has a count in WORD in the beginning, followed by
# real data.
#
###############################################################################
{
    my ($self, $offset, $pCallback) = @_;

    my $i;
    my $str;

    $str = BinaryFile::GetWordBytes($self->{m_flatMaxItem} + 1);
    $str = $str . GetBytesFlat($self, $offset, $pCallback);
    return ($str);
}

# internal
sub GetBytes
###############################################################################
#
# This is called by NLSDataTable::AddTable()
#
###############################################################################
{
    my ($self, $offset) = @_;
    if ($self->{m_tableType} == 1)
    {
        return (GetBytesFlat($self, $offset));
    } elsif ($self->{m_tableType} == 2)
    {
        return (GetBytesCountedFlat($self, $offset));
    } elsif (($self->{m_tableType} == 8) || ($self->{m_tableType} == 12))
    {
        return (GetBytes12_4_4($self, $offset));
    }
    die ("DataTable::GetBytes(): Unknown table type:" . $self->{m_tableType});

}

sub GetBytes12_4_4
{
    my ($self, $offset) = @_;

    my $bytes = [];

    my $PLANE_TABLE_HEADER_SIZE = 16;

    #
    # Write header (16 bytes), which contains:
    #    Offset to level 1 index table: 
    #

    # Write level 1 offset.
    # $offset += $PLANE_TABLE_HEADER_SIZE;
    # AddBytes($self, BinaryFile::GetDWordBytes($offset));
    # Write level 2 offset.
    #   The element size for level 1 table is 2 byte(a WORD).
    # $offset += ($#{$self->{m_level1Index}} + 1) * 2;
    # AddBytes($self, BinaryFile::GetDWordBytes($offset));
    # Write level 3 offset
    #   The element size for level 2 table is 2 byte (a WORD).
    # $offset += ($#{$self->{m_level2Index}} + 1) * 2;
    # AddBytes($self, BinaryFile::GetDWordBytes($offset));
    # Write level 3 size
    # AddBytes($self, BinaryFile::GetDWordBytes($#{$self->{m_level3Index}}+1));

    # Write level 1 table
    my $i;
    my $level1TableSize = ($#{$self->{m_level1Index}} + 1);   # An item in level 1 table in WORD.

    for ($i = 0; $i <= $#{$self->{m_level1Index}}; $i++)
    {
        # printf "%2x ",  $self->{m_level1Index}->[$i];    
        AddBytes($self, BinaryFile::GetWordBytes(($self->{m_level1Index}->[$i]) * 16 + $level1TableSize));
        $offset+=2;
    }

    my $level2TableSize = ($#{$self->{m_level2Index}} + 1);    # An item in level 2 table in WORD.
    # Write level 2 table
    for ($i = 0; $i <= $#{$self->{m_level2Index}}; $i++)
    {
        # printf "%2x ",  $self->{m_level2Index}->[$i];    
        # The index is based on WORD array.  Therefore, we have to adjust the index value based on the byte size of the final value.
        # byte value => divide by 2
        # word value -> divide by one
        # dword value -> multiply by 2.
        AddBytes($self, BinaryFile::GetWordBytes(hex($self->{m_level2Index}->[$i]) * $self->{m_valueByteSize} / 2 + $level1TableSize + $level2TableSize));
        $offset+=2;
    }

    # Write level 3 values by calling the callback functions.
    for ($i = 0; $i <= $#{$self->{m_level3Data}}; $i++)
    {
        # Call the callback function to get the bytes of the value.
        my $valueBytes = $self->{m_pGetValueBytesCallback}->($self->{m_level3Data}->[$i]);
        AddBytes($self, $valueBytes);
        $offset += length($valueBytes);
    }

    AddBytes($self, BinaryFile::GetByteBoundaryBytes(16, $offset, 0xEE));
    
    return ($self->{m_bytes});
}

sub PrintTable
{
    my ($self, $hFile) = @_;
    if ($self->{m_tableType} == 8 || $self->{m_tableType} == 12) 
    {
        PrintTable12_4_4($self, $hFile);
    } else 
    {
        die "DataTable.pm: PrintTable() is not supported for table type " . $self->{m_tableType};
    }
}

sub PrintTable12_4_4
{
    my ($self, $hFile) = @_;
    my $i;
    {
        my $count = $self->{m_planeCharCountArray};
        if ( $count > 0)
        {
            printf $hFile "Total defined characters: $count\n";
            printf $hFile "Level 1 Count = %d\n", $#{$self->{m_level1Index}} + 1;
            printf $hFile "Level 1 index:\n";
            my $element;
            for ($i = 0; $i <= $#{$self->{m_level1Index}}; $i++)
            {
                if ($i % 16 == 0)
                {
                    printf $hFile "\n%04x: ", $i;
                }
                printf $hFile ("%02x,", $self->{m_level1Index}->[$i]);
            }
            printf $hFile "\n";

            # The level 2 table is grouped in 16 elements.
            my $levelCount = ($#{$self->{m_level2Index}} + 1)/16;
            printf $hFile "    Level 2 Count = %d (0x%02x)\n", $levelCount, $levelCount;
            printf $hFile "    Level 2 index:\n";
            my $element;
            for ($i = 0; $i <= $#{$self->{m_level2Index}}; $i++)
            {
                if ($i % 16 == 0)
                {
                     printf $hFile "\n    %02x:", ($i/16);
                }
                printf $hFile ("%04x,", hex($self->{m_level2Index}->[$i]));
            }
            print $hFile "\n";

            $levelCount = ($#{$self->{m_level3Data}} + 1)/16;
            printf $hFile "        Level 3 Count = %d (0x%04x)\n", $levelCount, $levelCount;
            printf $hFile "        Level 3 data:\n";
            my $element;
            for ($i = 0; $i <= $#{$self->{m_level3Data}}; $i++)
            {
                if ($i % 16 == 0)
                {
                    printf $hFile "\n        %04x:", $i;
                }
                printf $hFile ($self->{m_level3Data}->[$i] . ",");
            }
            
            printf $hFile ("\n");
            printf $hFile ("\n");
        }
    }
}

sub WriteTable
{
    my ($self, $fileName, $pHeaderCallback, $pCallBack) = @_;


    my $offset = 0;
    # Write name: WCHAR[32]
    BinaryFile::WriteFixedWideString(*OUTPUTFILE{IO}, $fileName, 16);
    $offset += 16 * 2;

    # Write version: WORD[4]
    BinaryFile::WriteWord(*OUTPUTFILE{IO}, 0);
    BinaryFile::WriteWord(*OUTPUTFILE{IO}, 0);
    BinaryFile::WriteWord(*OUTPUTFILE{IO}, 0);
    BinaryFile::WriteWord(*OUTPUTFILE{IO}, 0);
    $offset += 4 * 2;

    # Write table type: WORD[1]

    BinaryFile::WriteWord(*OUTPUTFILE{IO}, $self->{m_TableType});
    $offset += 2;

    $offset += BinaryFile::WriteByteBoundary(*OUTPUTFILE{IO}, 16, $offset, 0xEE);

    $offset += 17 * 4;

    my $planeOffset = $offset + BinaryFile::GetByteBoundary(16, $offset) + $pHeaderCallback->(*OUTPUTFILE{IO}, 0);
    
    # Write table index
    {
        if ($self->{m_pPlaneTableSize} > 0)
        {
            BinaryFile::WriteDWord(*OUTPUTFILE{IO}, $planeOffset);
            $planeOffset += 16;
            $planeOffset += $self->{m_pPlaneTableSize};
            $planeOffset += BinaryFile::GetByteBoundary(16, $planeOffset);
        } else
        {
            BinaryFile::WriteDWord(*OUTPUTFILE{IO}, 0);
        }
    }
    my $i;
    $offset += BinaryFile::WriteByteBoundary(*OUTPUTFILE{IO}, 16, $offset, 0xEE);

    # Now we are in 16-byte boundary.
    $offset += $pHeaderCallback->(*OUTPUTFILE{IO}, 1);
    
    
    {
        if ($self->{m_pPlaneTableSize} > 0)
        {
            $offset += Write844Table($self, *OUTPUTFILE{IO}, $offset, $pCallBack, 1);
        }
    }
    
    close OUTPUTFILE;
}

sub Write844Table
###############################################################################
#
# Actions:
#    Generate the 12:4:4 Table
# Parameteres:
#    $hFile    The output file handle.
#    $offset    
#
# Returns:
#   The total size in byte of this 8:4:4 table.
#
###############################################################################
{
    my ($self, $hFile, $offset, $pCallBack, $isWriteTable) = @_;

    my $PLANE_TABLE_HEADER_SIZE = 16;

    #
    # Write header (16 bytes), which contains:
    #    Offset to level 1 index table: 
    #
    
    # Write level 1 offset.
    $offset += $PLANE_TABLE_HEADER_SIZE;
    BinaryFile::WriteDWord($hFile, $offset);
    # Write level 2 offset.
    #   The element size for level 1 table is 1 byte.
    $offset += ($#{$self->{m_level1Index}} + 1) * 1;
    BinaryFile::WriteDWord($hFile, $offset);
    # Write level 3 offset
    #   The element size for level 2 table is 2 byte (a WORD).
    $offset += ($#{$self->{m_level2Index}} + 1) * 2;
    BinaryFile::WriteDWord($hFile, $offset);
    # Write level 3 size
    BinaryFile::WriteDWord($hFile, $#{$self->{m_level3Index}}+1);

    # Write level 1 table
    my $i;

    for ($i = 0; $i <= $#{$self->{m_level1Index}}; $i++)
    {
        # printf "%2x ",  $self->{m_level1Index}->[$i];    
        BinaryFile::WriteByte($hFile, $self->{m_level1Index}->[$i]);
    }

    # Write level 2 table
    for ($i = 0; $i <= $#{$self->{m_level2Index}}; $i++)
    {
        # printf "%2x ",  $self->{m_level2Index}->[$i];    
        BinaryFile::WriteWord($hFile, hex($self->{m_level2Index}->[$i]));
    }

    # Write level 3 values by calling the callback functions.
    for ($i = 0; $i <= $#{$self->{m_level3Data}}; $i++)
    {
        $pCallBack->($hFile, $self->{m_level3Data}->[$i]);
    }

    $offset += $self->{m_pPlaneTableSize};
    my $extraByte += BinaryFile::WriteByteBoundary($hFile, 16, $offset, 0xEE);

    printf("12:4:4 Table is written.\n");
    return ($PLANE_TABLE_HEADER_SIZE + $self->{m_pPlaneTableSize} + $extraByte);
}

1;
