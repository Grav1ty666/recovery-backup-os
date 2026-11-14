// Firmware entry helper. Intended for a UEFI virtual machine only until validated.
using System;
using System.Globalization;
internal static class FirmwareHelper
{
    static int Main(string[] args)
    {
        try {
            if (args.Length == 2 && args[0] == "uninstall") { FirmwareBootDraft.RemoveRecoveryEntries(Guid.Parse(args[1])); return 0; }
            if (args.Length != 4) throw new ArgumentException("partition-guid partition-number start-lba length-lba");
            Guid id = Guid.Parse(args[0]);
            uint number = UInt32.Parse(args[1], CultureInfo.InvariantCulture);
            ulong start = UInt64.Parse(args[2], CultureInfo.InvariantCulture);
            ulong length = UInt64.Parse(args[3], CultureInfo.InvariantCulture);
            byte[] option = FirmwareBootDraft.BuildLoadOption(id, number, start, length, @"\EFI\clonezilla\grubx64.efi", "Recover and Backup OS");
            ushort created = FirmwareBootDraft.Register(option);
            Console.WriteLine("UEFI entry: Boot" + created.ToString("X4"));
            return 0;
        } catch (Exception e) { try { System.IO.File.AppendAllText(System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "error-details.log"), DateTime.Now.ToString("s") + " 0xE0010008 " + e + Environment.NewLine); } catch { } return 1; }
    }
}
