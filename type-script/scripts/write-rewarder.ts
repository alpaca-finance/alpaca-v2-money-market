import { Command } from "commander";
import { ConfigFileHelper } from "../file-helper.ts/config-file.helper";
import { MiniFLPool } from "../interfaces";

async function main(id: string, name: string, stakingToken: string) {
  const configFileHelper = new ConfigFileHelper();

  const newMiniFLPool: MiniFLPool = {
    id: Number(id),
    name,
    stakingToken,
    rewarders: [],
  };

  configFileHelper.addMiniFLPool(newMiniFLPool);
  console.log("✅ Done");
}

const program = new Command();
program.requiredOption("-i, --id <id>");
program.requiredOption("-n, --name <name>");
program.requiredOption("-token, --stakingToken <stakingToken>");

program.parse(process.argv);

const options = program.opts();

main(options.id, options.name, options.stakingToken)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
