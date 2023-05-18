import { Command } from "commander";
import { ConfigFileHelper } from "../../deploy/file-helper.ts/config-file.helper";

async function main(miniFLpId: number, rewarderAddress: string[]) {
  const configFileHelper = new ConfigFileHelper();

  configFileHelper.setMiniFLPoolRewarders(miniFLpId, rewarderAddress);
  console.log("✅ Done");
}

const program = new Command();
program.requiredOption("-p, --pid <pid>");
program.requiredOption("-r, --rewarderAddress <rewarderAddress...>");

program.parse(process.argv);

const options = program.opts();

main(options.pid, options.rewarderAddress)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
