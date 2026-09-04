CREATE TABLE IF NOT EXISTS `qbpolice_ballistic_casings` (
  `case_id` VARCHAR(64) NOT NULL,
  `round_id` VARCHAR(96) NOT NULL,
  `weapon_serial` VARCHAR(96) NOT NULL,
  `weapon_name` VARCHAR(96) NOT NULL,
  `ammo_type` VARCHAR(64) DEFAULT NULL,
  `lot` VARCHAR(64) DEFAULT NULL,
  `x` DOUBLE NOT NULL,
  `y` DOUBLE NOT NULL,
  `z` DOUBLE NOT NULL,
  `bucket` INT NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `collected_by` VARCHAR(64) DEFAULT NULL,
  `collected_at` TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`case_id`),
  KEY `idx_ballistic_serial` (`weapon_serial`),
  KEY `idx_ballistic_collected` (`collected_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
