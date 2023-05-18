import { Command } from "commander";
import { ConfigFileHelper } from "../../deploy/file-helper.ts/config-file.helper";
import { Rewarder } from "../../deploy/interfaces";

async function main(name: string, address: string, rewardToken: string) {
  const configFileHelper = new ConfigFileHelper();

  const rewarder: Rewarder = {
    name,
    address,
    rewardToken,
  };

  configFileHelper.addRewarder(rewarder);
  console.log("✅ Done");
}

const program = new Command();
program.requiredOption("-n, --name <name>");
program.requiredOption("-a, --address <address>");
program.requiredOption("-r, --rewardToken <rewardToken>");

program.parse(process.argv);

const options = program.opts();

main(options.name, options.address, options.rewardToken)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
