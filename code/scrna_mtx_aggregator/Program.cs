using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

if (args.Length != 6)
{
    Console.Error.WriteLine(
        "Usage: scrna_mtx_aggregator <matrix.mtx.gz> <cell-map.txt> <target-rows.txt> " +
        "<counts.bin> <reconstructed-target.tsv.gz> <summary.json>"
    );
    return 2;
}

string matrixPath = args[0];
string cellMapPath = args[1];
string targetRowsPath = args[2];
string countsPath = args[3];
string reconstructedTargetPath = args[4];
string summaryPath = args[5];

int[] cellMap = File.ReadLines(cellMapPath).Select(int.Parse).ToArray();
int sampleCount = cellMap.Max();
HashSet<int> targetRows = File.ReadLines(targetRowsPath).Select(int.Parse).ToHashSet();

using FileStream compressed = File.OpenRead(matrixPath);
using GZipStream decompressed = new(compressed, CompressionMode.Decompress);
FastIntegerReader reader = new(decompressed);

int geneCount = reader.ReadInt();
int matrixCellCount = reader.ReadInt();
long expectedEntries = reader.ReadLong();
bool[] isTargetRow = new bool[geneCount + 1];
foreach (int row in targetRows)
{
    isTargetRow[row] = true;
}
if (matrixCellCount != cellMap.Length)
{
    throw new InvalidDataException(
        $"Cell map length {cellMap.Length} differs from matrix columns {matrixCellCount}."
    );
}

long outputLength = (long)geneCount * sampleCount;
if (outputLength > int.MaxValue)
{
    throw new InvalidDataException("Aggregated matrix exceeds the CLR single-array limit.");
}

int[] counts = new int[(int)outputLength];
long[] observedSampleTotals = new long[sampleCount];
long processedEntries = 0;
long selectedEntries = 0;
long reconstructedTargetEntries = 0;

Directory.CreateDirectory(Path.GetDirectoryName(countsPath)!);
using FileStream targetFile = File.Create(reconstructedTargetPath);
using GZipStream targetGzip = new(targetFile, CompressionLevel.SmallestSize);
using StreamWriter targetWriter = new(targetGzip, new UTF8Encoding(false), bufferSize: 1 << 20);

while (processedEntries < expectedEntries)
{
    int row = reader.ReadInt();
    int column = reader.ReadInt();
    int value = reader.ReadInt();
    processedEntries++;

    int sampleIndex = cellMap[column - 1];
    if (sampleIndex > 0)
    {
        int outputIndex = (row - 1) * sampleCount + (sampleIndex - 1);
        counts[outputIndex] += value;
        observedSampleTotals[sampleIndex - 1] += value;
        selectedEntries++;
    }

    if (isTargetRow[row])
    {
        targetWriter.Write(row);
        targetWriter.Write('\t');
        targetWriter.Write(column);
        targetWriter.Write('\t');
        targetWriter.Write(value);
        targetWriter.Write('\n');
        reconstructedTargetEntries++;
    }

    if (processedEntries % 100_000_000 == 0)
    {
        Console.Error.WriteLine($"Processed {processedEntries:N0} / {expectedEntries:N0} entries");
    }
}
targetWriter.Flush();

using (FileStream output = File.Create(countsPath))
using (BinaryWriter writer = new(output, Encoding.UTF8, leaveOpen: true))
{
    writer.Write(geneCount);
    writer.Write(sampleCount);
    output.Write(MemoryMarshal.AsBytes(counts.AsSpan()));
}

string totalsPath = Path.ChangeExtension(countsPath, ".sample_totals.tsv");
using (StreamWriter totalsWriter = new(totalsPath, false, new UTF8Encoding(false)))
{
    totalsWriter.WriteLine("sample_index\traw_matrix_total_umi");
    for (int index = 0; index < observedSampleTotals.Length; index++)
    {
        totalsWriter.WriteLine($"{index + 1}\t{observedSampleTotals[index]}");
    }
}

var summary = new
{
    gene_count = geneCount,
    matrix_cell_count = matrixCellCount,
    sample_count = sampleCount,
    expected_nonzero_entries = expectedEntries,
    processed_nonzero_entries = processedEntries,
    selected_cell_nonzero_entries = selectedEntries,
    target_rows = targetRows.Count,
    reconstructed_target_entries = reconstructedTargetEntries,
    counts_binary_bytes = new FileInfo(countsPath).Length,
};
File.WriteAllText(summaryPath, JsonSerializer.Serialize(summary, new JsonSerializerOptions
{
    WriteIndented = true,
}));
Console.WriteLine(JsonSerializer.Serialize(summary, new JsonSerializerOptions { WriteIndented = true }));
return 0;

sealed class FastIntegerReader
{
    private readonly Stream stream;
    private readonly byte[] buffer = new byte[1 << 20];
    private int position;
    private int length;
    private bool atLineStart = true;

    public FastIntegerReader(Stream stream)
    {
        this.stream = stream;
    }

    public int ReadInt()
    {
        long value = ReadLong();
        if (value > int.MaxValue)
        {
            throw new InvalidDataException($"Integer value {value} exceeds Int32 range.");
        }
        return (int)value;
    }

    public long ReadLong()
    {
        int current;
        while (true)
        {
            current = ReadByte();
            if (current < 0)
            {
                throw new EndOfStreamException("Unexpected end of Matrix Market stream.");
            }
            if (atLineStart && current == '%')
            {
                while (current >= 0 && current != '\n')
                {
                    current = ReadByte();
                }
                atLineStart = true;
                continue;
            }
            if (current == '\n')
            {
                atLineStart = true;
                continue;
            }
            if (current == ' ' || current == '\t' || current == '\r')
            {
                continue;
            }
            break;
        }

        atLineStart = false;
        long value = 0;
        while (current >= '0' && current <= '9')
        {
            value = value * 10 + (current - '0');
            current = ReadByte();
        }
        if (current == '\n')
        {
            atLineStart = true;
        }
        return value;
    }

    private int ReadByte()
    {
        if (position >= length)
        {
            length = stream.Read(buffer, 0, buffer.Length);
            position = 0;
            if (length == 0)
            {
                return -1;
            }
        }
        return buffer[position++];
    }
}
