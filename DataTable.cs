using System;
using System.Collections.Generic;

namespace GenUnicodeProp
{
	internal sealed class DataTable
	{
		private readonly byte TableType;
		private readonly string DefaultValue;
		private readonly byte ValueByteSize;
		private readonly Func<string, byte[]> GetValueBytesCallback;

		// This contains the data mapping between codepoints and values.
		private readonly SortedDictionary<uint, string> RawData = new SortedDictionary<uint, string>();

		// The following are all 2-dimentional array.  
		// The first dimention is the plane, and the second dimention is the index or values for that plane.
		private readonly List<byte> Level1Index = new List<byte>();
		private readonly List<ushort> Level2Index = new List<ushort>();
		private readonly List<string> Level3Data = new List<string>();

		public DataTable(byte tableType, string defaultValue, byte valueByteSize, Func<string, byte[]> getValueBytesCallback)
		{
			if(tableType != 1 && tableType != 12) throw new ArgumentException($"Invalid table type [{tableType}].");
			TableType = tableType;

			// If a codepoint does not have data, this specifies the default value.    
			DefaultValue = defaultValue;

			ValueByteSize = valueByteSize;
			GetValueBytesCallback = getValueBytesCallback;
		}

		//   Actions:
		//       Add the value data for the specified codepoint.
		//
		//   Parameters:
		//        $codepoint    The codepoint to be added
		//        $value        The value for the specified codepoint
		public void AddData(uint codepoint, string value) => RawData[codepoint] = value;

		public void AddData(uint key, byte value) => AddData(key, value.ToString());

		public byte[] GetBytesFlat()
		{
			var str = new List<byte>();
			foreach(var v in RawData.Values)
				str.AddRange(GetValueBytesCallback(v ?? DefaultValue));
			return str.ToArray();
		}

		/// <summary>
		/// Create the 12:4:4 data table structure after all the codepoint/value pairs are added by using AddData.
		/// </summary>
		public void GenerateTable12_4_4()
		{
			if(TableType != 12) throw new InvalidOperationException("Invalid table type. The value should be 12.");
			Console.WriteLine("Process 12:4:4 table.");

			var ch = 0u;

			// There is data in the plane.  Create 8:4:4 table for this plane.
			var level2Hash = new Dictionary<string, byte>();
			var level3Hash = new Dictionary<string, ushort>();

			const int planes = 17;
			const int level2block = 16;
			const int level3block = 16;

			var level3RowData = new string[level3block];
			var level2RowData = new ushort[level2block];

			// Process plan 0 ~ 16.
			for(var i = 0;i < 256 * planes;i++)
			{
				// Generate level 1 indice

				// This is the row data which contains a row of indice for level 2 table.
				for(var j = 0;j < level2RowData.Length;j++)
				{
					// Generate level 2 indice
					for(var k = 0;k < level3RowData.Length;k++)
					{
						// Generate level 3 values by grouping 16 values together.
						// Each element of the 16 value group is seperated by ";"
						if(!RawData.TryGetValue(ch, out var value)) value = DefaultValue;

						level3RowData[k] = value;
						ch++;
					}

					// Check if the pattern of these 16 values happens before.
					var level3key = string.Join(";", level3RowData);
					if(!level3Hash.TryGetValue(level3key, out var valueInHash3))
					{
						// This is a new group in the level 3 values.
						// Get the current count of level 3 group count for this plane.
						valueInHash3 = checked((ushort)Level3Data.Count);
						// Store this count to the hash table, keyed by the pattern of these 16 values.
						level3Hash[level3key] = valueInHash3;

						// Populate the 16 values into level 3 data table for this plane.
						Level3Data.AddRange(level3RowData);
					}
					level2RowData[j] = valueInHash3;
				}

				var level2key = string.Join(";", level2RowData);
				if(!level2Hash.TryGetValue(level2key, out var valueInHash))
				{
					// Get the count of the current level 2 index table.
					valueInHash = checked((byte)(Level2Index.Count / level3block));
					level2Hash[level2key] = valueInHash;

					// Populate the 16 values into level 2 data table for this plane.
					Level2Index.AddRange(level2RowData);
				}
				// Populate the index values into level 1 index table.
				Level1Index.Add(valueInHash);
			}

			var level1Count = Level1Index.Count;
			var level2Count = Level2Index.Count;
			var level3Count = Level3Data.Count;

			Console.WriteLine($"level 1: {level1Count}");
			Console.WriteLine($"level 2: {level2Count}");
			Console.WriteLine($"level 3: {level3Count}");

			var planeTableSize
					= level1Count * 1 +    // Level 1 index value is BYTE.
						level2Count * 2 +    // Level 2 index value is WORD.
						level3Count * ValueByteSize;
			Console.WriteLine(planeTableSize);
		}

		public byte[][] GetBytes12_4_4()
		{
			// Write level 1 table
			// An item in level 1 table in WORD.
			var level1 = new List<byte>();
			for(var i = 0;i < Level1Index.Count;i++)
				level1.AddRange(BitConverter.GetBytes((ushort)(Level1Index[i] * 16 + Level1Index.Count)));

			// Write level 2 table
			// An item in level 2 table in WORD.
			var level2 = new List<byte>();
			for(var i = 0;i < Level2Index.Count;i++)
			{
				// The index is based on WORD array.  Therefore, we have to adjust the index value based on the byte size of the final value.
				// byte value => divide by 2
				// word value -> divide by one
				// dword value -> multiply by 2.
				level2.AddRange(BitConverter.GetBytes((ushort)(Level2Index[i] * ValueByteSize / 2 + Level1Index.Count + Level2Index.Count)));
			}

			// Write level 3 values by calling the callback functions.
			var level3 = new List<byte>();
			for(var i = 0;i < Level3Data.Count;i++)
			{
				// Call the callback function to get the bytes of the value.
				level3.AddRange(GetValueBytesCallback(Level3Data[i]));
			}
			level3.AddRange(GetByteBoundaryBytes(16, level1.Count + level2.Count + level3.Count - 4/*-4 is a BUG in original script*/, 0xEE));

			return new[] { level1.ToArray(), level2.ToArray(), level3.ToArray() };
		}

		private static byte[] GetByteBoundaryBytes(int byteBoundary, int offset, byte byteToFill)
		{
			var remainder = offset % byteBoundary;
			if(remainder == 0) return Array.Empty<byte>();

			var res = new byte[byteBoundary - remainder];
			Array.Fill(res, byteToFill);
			return res;
		}
	}
}